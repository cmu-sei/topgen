#!/bin/bash

# Configure virtual mail service for TopGen
# (glsomlo@cert.org, February 2016)

# input: topgen virtual mail config file
VMAIL_CFG='/etc/topgen/vmail.cfg'

# topgen directory structure:
TOPGEN_VARLIB='/var/lib/topgen'

# if "yes", do not print out warnings:
let VERBOSE=0

# if "yes", force/overwrite any prior existing configuration
FORCE_GEN='no'

###########################################################################
####    NO FURTHER USER-SERVICEABLE PARTS BEYOND THIS POINT !!!!!!!    ####
###########################################################################

USAGE_BLURB="
Usage: $0 [-c <vmail_config>] [-t <target_directory>]

The optional command line arguments are:

    -c <vmail_config>     file containing virtual mail domain configuration
                          entries, one per line. The format of each line is:
                          <hostname>.<domain> <ip_addr> <usr1>:<pw1> <usr2>:...
                          (default: $VMAIL_CFG).

    -t <target_directory> directory where all resulting configuration files
                          are stored;
                          (default: $TOPGEN_VARLIB).

    -f                    don't stop if encountering pre-existing configuration;
                          instead, forcibly remove & re-create  configuration.
                          CAUTION: pre-existing configuration will be lost!

    -v                    increase verbosity level (may be used multiple times);
                          (default: $VERBOSE).

Generate virtual mail server configuration for the (domain, server, users)
sets given in a configuration file. Place configuration data under
<target_directory>/etc/postfix/, and ensure <target_directory>/vmail/ exists
and is owned by dovenull:dovenull.
" # end usage blurb

# process command line options:
OPTIND=1
while getopts "c:t:fvh?" OPT; do
  case "$OPT" in
  s)
    VMAIL_CFG=$OPTARG
    ;;
  t)
    TOPGEN_VARLIB=$OPTARG
    ;;
  f)
    FORCE_GEN='yes'
    ;;
  v)
    let VERBOSE++
    ;;
  *)
    echo "$USAGE_BLURB"
    exit 0
    ;;
  esac
done

# we should be left with NO FURTHER arguments on the command line:
shift $((OPTIND-1))
[ -z "$@" ] || {
  echo "
ERROR: invalid argument: $@

$USAGE_BLURB
"
  exit 1
}

# once $TOPGEN_VARLIB is set, these are its relevant subdirectories:
VMAIL_CFGDIR="$TOPGEN_VARLIB/etc/postfix"
VMAIL_MBOXDIR="$TOPGEN_VARLIB/vmail"
VMAIL_HOSTFILE="$TOPGEN_VARLIB/etc/hosts.vmail"

# assert existence of required input files and target folders:
[ -s "$VMAIL_CFG" -a \
  -d "$VMAIL_CFGDIR" -a -d "$VMAIL_MBOXDIR" ] || {
  echo "
ERROR: file \"$VMAIL_CFG\" and
       folders \"$VMAIL_CFGDIR\", and
               \"$VMAIL_MBOXDIR\" MUST exist
       before running this command!

$USAGE_BLURB
"
  exit 1
}

# assert vmail config folder is empty:
[ "$FORCE_GEN" == "yes" ] && rm -rf $VMAIL_CFGDIR/*
[ -n "$(ls -A $VMAIL_CFGDIR)" ] && {
  echo "
ERROR: folder \"$VMAIL_CFGDIR\" MUST be empty
       before running this command!

$USAGE_BLURB
"
  exit 1
}

# assert non-existence of vmail hosts file
[ "$FORCE_GEN" == "yes" ] && rm -rf $VMAIL_HOSTFILE
[ -s "$VMAIL_HOSTFILE" ] && {
  echo "
ERROR: file \"$VMAIL_HOSTFILE\" must NOT exist!
       Please remove it manually before re-running this command!

$USAGE_BLURB
"
  exit 1
}

# assert mailbox data folder is owned by dovenull:
[ "$(stat -c %U $VMAIL_MBOXDIR)" != "dovenull" ] && {
  echo "
ERROR: folder \"$VMAIL_MBOXDIR\" MUST be owned by \"dovenull\"!

$USAGE_BLURB
"
  exit 1
}


# Start by generating domain-specific configuration entries
# from the parsed content of $VMAIL_CFG:
#
cat $VMAIL_CFG | grep -v ^# | while read HOST ADDR USERS; do

  # skip if no users:
  [ -n "$USERS" ] || continue

  DOMAIN=${HOST#*.}

  # add ipaddr-fqdn pair to vmail specific hosts file:
  echo "$ADDR $HOST" >> $VMAIL_HOSTFILE

  # add domain to pf_virt_dom (for postfix:master.cf:$virtual_mailbox_domains)
  echo $DOMAIN >> $VMAIL_CFGDIR/pf_virt_dom

  # add domain-specific outbound sender to postfix:master.cf and pf_dom_send:
  cat >> $VMAIL_CFGDIR/master.cf <<- EOT
	mx_$DOMAIN
	           unix  -       -       n       -       -       smtp
	    -o smtp_helo_name=$DOMAIN
	    -o smtp_bind_address=$ADDR
	EOT
  # (for postfix:master.cf:$sender_dependent_default_transport_maps)
  echo "$DOMAIN mx_$DOMAIN" >> $VMAIL_CFGDIR/pf_dom_send

  # add domain imap server ip to dc_addr_dom (for dovecot:dovecot.conf)
  echo "$ADDR:::::::domain=$DOMAIN" >> $VMAIL_CFGDIR/dc_addr_dom

  # create domain users (pf_usr_mbox for mail dirs, dc_usr_pass for auth):
  for U in $USERS; do
    USER=${U%:*}
    PASS=${U#*:}
    echo "$USER@$DOMAIN $DOMAIN/$USER/" >> $VMAIL_CFGDIR/pf_usr_mbox
    echo "$USER@$DOMAIN:{PLAIN}$PASS" >> $VMAIL_CFGDIR/dc_usr_pass
  done

done

# If, for some reason, no domain-specific config entries were generated
# (e.g., empty $VMAIL_CFG file), skip generating meaningless global configs:
[ -s "$VMAIL_HOSTFILE" -a -s "$VMAIL_CFGDIR/pf_virt_dom" -a \
  -s "$VMAIL_CFGDIR/master.cf" -a -s "$VMAIL_CFGDIR/pf_dom_send" -a \
  -s "$VMAIL_CFGDIR/dc_addr_dom" -a -s "$VMAIL_CFGDIR/pf_usr_mbox" -a \
  -s "$VMAIL_CFGDIR/dc_usr_pass" ] || exit 0

# generate fixed (components of) postfix & dovecot config files:
#

DOVENULL_ID=$(getent passwd dovenull | cut -d: -f3,4)

cat > $VMAIL_CFGDIR/main.cf <<- EOT
	# Local mail: when people email <foo>@topgen.info, local aliases get
	#  mail delivered inside the topgen container, in /var/spool/mail/<foo>
	#
	mydomain = topgen.info
	myhostname = greybox.topgen.info
	mynetworks = 127.0.0.0/8
	mydestination = localhost, \$myhostname, localhost.\$mydomain, \$mydomain
	# if e.g. root tries to read its @topgen.info mail via cmdline,
	#  we need these entries to be local to our container,
	#  and match expected defaults:
	data_directory = /var/lib/postfix
	queue_directory = /var/spool/postfix
	mail_spool_directory = /var/spool/mail

	# virtual multi-domain mailserver setup:
	#
	virtual_mailbox_domains = $VMAIL_CFGDIR/pf_virt_dom
	virtual_mailbox_base = $VMAIL_MBOXDIR
	virtual_mailbox_maps =
	      texthash:$VMAIL_CFGDIR/pf_usr_mbox
	      static:DFLT
	# use already existing dovenull account numerical uid/gid:
	virtual_uid_maps = static:${DOVENULL_ID%:*}
	virtual_gid_maps = static:${DOVENULL_ID#*:}
	# if recipient domain not local, use correct sender "personality":
	# (NOTE: map sender domains to transport/service entries in master.cf)
	sender_dependent_default_transport_maps =
	      texthash:$VMAIL_CFGDIR/pf_dom_send

	# force remote clients to authenticate:
	# (NOTE: see also "submission" entry in master.cf;
	#        "smtps", identically configured, would listen
	#        on deprecated port 465)
	#
	smtpd_sasl_auth_enable = yes
	smtpd_sasl_type = dovecot
	# auth service socket from dovecot (relative to \$queue_directory):
	smtpd_sasl_path = private/auth
	smtpd_client_restrictions =
	      permit_mynetworks,
	      permit_sasl_authenticated,
	      reject
	# enable compatibility with outlook/exchange smtp auth:
	broken_sasl_auth_clients = yes

	# force remote clients to use encryption:
	#
	smtpd_tls_security_level = encrypt
	smtpd_tls_cert_file = $VMAIL_CFGDIR/pf_tls.cer
	smtpd_tls_key_file = $VMAIL_CFGDIR/pf_tls.key
	EOT

cat > $VMAIL_CFGDIR/dovecot.conf <<- EOT
	log_path = /var/log/dovecot.log
	mbox_write_locks = fcntl

	ssl = required
	ssl_cert = <$VMAIL_CFGDIR/dc_tls.cer
	ssl_key = <$VMAIL_CFGDIR/dc_tls.key

	auth_mechanisms = plain login cram-md5

	# set domain based on local IP used by client:
	passdb {
	  driver = passwd-file
	  args = username_format=%l $VMAIL_CFGDIR/dc_addr_dom
	  result_success = continue
	}

	passdb {
	  driver = passwd-file
	  args = $VMAIL_CFGDIR/dc_usr_pass
	}

	# match postfix location:
	mail_location = maildir:$VMAIL_MBOXDIR/%d/%n

	userdb {
	  driver = static
	  args = uid=dovenull gid=dovenull home=$VMAIL_MBOXDIR/%d/%n
	}

	# auth service available to postfix
	# (as postfix:main.cf:\$smtpd_sasl_path):
	service auth {
	  # "/var/spool/postfix" is postfix:main.cf:\$queue_directory;
	  unix_listener /var/spool/postfix/private/auth {
	    mode = 0660
	    user = postfix
	    group = postfix
	  }
	}
	EOT

# this must be *prepended* to what's currently in master.cf:
sed -i '1 {
h
r /dev/stdin
g
N
}' $VMAIL_CFGDIR/master.cf <<- "EOT"
	# service  type private unpriv  chroot  wakeup  maxproc  cmd+args
	# name          (yes)   (yes)   (no)    (never) (100)
	# ======================================================================
	smtp       inet  n       -       n       -       -       smtpd
	submission inet  n       -       n       -       -       smtpd
	    -o smtpd_sasl_auth_enable=yes
	    -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
	    -o milter_macro_daemon_name=ORIGINATING
	pickup     unix  n       -       n       60      1       pickup
	cleanup    unix  n       -       n       -       0       cleanup
	qmgr       unix  n       -       n       300     1       qmgr
	tlsmgr     unix  -       -       n       1000?   1       tlsmgr
	rewrite    unix  -       -       n       -       -       trivial-rewrite
	bounce     unix  -       -       n       -       0       bounce
	defer      unix  -       -       n       -       0       bounce
	trace      unix  -       -       n       -       0       bounce
	verify     unix  -       -       n       -       1       verify
	flush      unix  n       -       n       1000?   0       flush
	proxymap   unix  -       -       n       -       -       proxymap
	proxywrite unix  -       -       n       -       1       proxymap
	smtp       unix  -       -       n       -       -       smtp
	relay      unix  -       -       n       -       -       smtp
	showq      unix  n       -       n       -       -       showq
	error      unix  -       -       n       -       -       error
	retry      unix  -       -       n       -       -       error
	discard    unix  -       -       n       -       -       discard
	local      unix  -       n       n       -       -       local
	virtual    unix  -       n       n       -       -       virtual
	lmtp       unix  -       -       n       -       -       lmtp
	anvil      unix  -       -       n       -       1       anvil
	scache     unix  -       -       n       -       1       scache
	EOT

#FIXME: maybe this could be the same cert+key, but then we'll HAVE to figure
#       out SELinux labeling (since postfix wants postfix_etc_t and dovecot
#       wants dovecot_etc_t, and right now one can't read files labeled for
#       the other !!!
openssl req -subj '/C=US/ST=PA/L=Pgh/O=CMU/OU=CERT/CN=smtp.topgen.info' \
            -newkey rsa:2048 -nodes -keyout $VMAIL_CFGDIR/pf_tls.key \
            -days 7300 -x509 -out $VMAIL_CFGDIR/pf_tls.cer 2>/dev/null
openssl req -subj '/C=US/ST=PA/L=Pgh/O=CMU/OU=CERT/CN=imap.topgen.info' \
            -newkey rsa:2048 -nodes -keyout $VMAIL_CFGDIR/dc_tls.key \
            -days 7300 -x509 -out $VMAIL_CFGDIR/dc_tls.cer 2>/dev/null

# FIXME: Sort out SELinux policy associated with topgen package !!!
# But, for now, let's label the relevant files and folders manually:
chcon -t dovecot_etc_t $VMAIL_CFGDIR/dovecot.conf $VMAIL_CFGDIR/dc_*
chcon -t postfix_etc_t $VMAIL_CFGDIR/*.cf $VMAIL_CFGDIR/pf_*
chcon -R -t mail_spool_t $VMAIL_MBOXDIR
