#!/bin/bash

# Generate TOR DA keys and config file for TopGen
# (glsomlo@cert.org, May 2018)

# TopGen home directory:
TG_DIR='/var/lib/topgen'

# TOR DA fqdn:
TDA_HOST='topgen.info'

###########################################################################
####    NO FURTHER USER-SERVICEABLE PARTS BEYOND THIS POINT !!!!!!!    ####
###########################################################################

PATH='/usr/bin:/usr/sbin'

# if "yes", force/overwrite prior/existing configuration
FORCE_GEN='no'

# usage blurb (to be printed with error messages):
USAGE_BLURB="
Usage: $0 [-t <target_directory>] [-n <da_hostname>]

The optional command line arguments are:

    -t <target_directory> base directory relative to which all
                          other configuration is located;
                          (default: $TG_DIR).

    -n <da_hostname>      fully qualified host name of the TOR
                          Directory Authority, also shared with
                          the virtual Web host representing the
                          simulator's front page;
                          (default: $TDA_HOST).

    -f                    forcibly overwrite and re-create any
                          pre-existing configuration elements.

Generate TOR Directory Authority keys and a corresponding sample
config file. A link to the config file will also be inserted into
the virtual Web host representing the simulator's front page.
" # end usage blurb

# process command line options:
OPTIND=1
while getopts "fh?" OPT; do
  case "$OPT" in
  t)
    TG_DIR=$OPTARG
    ;;
  n)
    TDA_HOST=$OPTARG
    ;;
  f)
    FORCE_GEN='yes'
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

# string matching mention of the Tor DA in various files:
TDA_STR='TOR Directory Authority'

# once $TG_CFG is set, these are the relevant elements underneath:

# TopGen config directory:
TG_CFG="$TG_DIR/etc"

# TopGen Web hosts file:
TG_WHF="$TG_CFG/hosts.nginx"

# TOR config directory:
TOR_CFG="$TG_CFG/tor"

# TopGen vhost folder and index.html file:
TG_VHOST="$TG_DIR/vhosts/$TDA_HOST"
TG_INDEX="$TG_VHOST/index.html"

# assert existence of required input files and target folders:
[ -s "$TG_WHF" -a -s "$TG_INDEX" ] || {
  echo "
ERROR: files \"$TG_WHF\" and
             \"$TG_INDEX\" MUST exist
       before running this command!
"
  exit 1
}

# parse DA ip-addr from TopGen Web hosts file:
TDA_ADDR=$(grep " $TDA_HOST$" "$TG_WHF" | cut -d' ' -f1)
[ -n "$TDA_ADDR" ] || {
  echo "
ERROR: Could not parse IP address of DA host \"$TDA_HOST\"
       from file \"$TG_WHF\"!
"
  exit 1
}

# remove previously existing settings if "-f" flag was invoked:
[ "$FORCE_GEN" == "yes" ] && {
  rm -rf "$TOR_CFG"
  sed -i "/$TDA_STR/d" "$TG_INDEX"
}

# at this point there should not be any TOR DA configuration present:
[ -d "$TOR_CFG" ] || grep -q "$TDA_STR" "$TG_INDEX" && {
  echo "
ERROR: directory \"$TOR_CFG\" MUST NOT exist, and file
       \"$TG_INDEX\" MUST NOT reference
       a \"$TDA_STR\" before running this command!

$USAGE_BLURB
"
  exit 1
}

# generate router keys for the DA:
tor --datadirectory $TOR_CFG --list-fingerprint --orport 1 \
    --dirauthority "127.0.0.1:1 ffffffffffffffffffffffffffffffffffffffff" | \
  grep '\[err\]'

[ -s "$TOR_CFG/fingerprint" -a -d "$TOR_CFG/keys" ] || {
  echo "
ERROR: Command to create DA router keys failed to create file:
       \"$TOR_CFG/fingerprint\"
       and directory:
       \"$TOR_CFG/keys\"!
"
  exit 1
}

# generate DA certificate:
(
  cd "$TOR_CFG/keys"
  tor-gencert --create-identity-key -m 24 -a $TDA_ADDR:7000 \
              --passphrase-fd 0 <<<tartans1
)

[ -s "$TOR_CFG/keys/authority_certificate" ] || {
  echo "
ERROR: Failed to create DA certificate file:
       \"$TOR_CFG/keys/authority_certificate\"!
"
  exit 1
}

# generate tor config file:
TDA_FP=$(head -1 "$TOR_CFG/fingerprint" | cut -d' ' -f2)
TDA_V3ID=$(grep ^fingerprint "$TOR_CFG/keys/authority_certificate" | \
             cut -d' ' -f2)
cat > "$TOR_CFG/torrc" <<- EOT
	# common settings
	RunAsDaemon 1
	TestingTorNetwork 1
	AssumeReachable 1
	TestingConsensusMaxDownloadTries 2
	UseDefaultFallbackDirs 0
	DataDirectory /var/lib/tor
	PidFile /var/lib/tor/pid
	#Log notice file /var/lib/tor/notice.log
	Log info file /var/lib/tor/info.log
	SafeLogging 0

	# generated directory authority:
	DirAuthority orport=5000 v3ident=$TDA_V3ID $TDA_ADDR:7000 $TDA_FP

	# instance-specific settings (pass in via cmdline as needed):

	# routers (incl. dir-auth):
	#ORPort 5000

	# directory server(s) only:
	#DirPort 7000

	# directory authority only:
	#Address $TDA_ADDR
	#OutboundBindAddress $TDA_ADDR
	#AuthoritativeDirectory 1
	#V3AuthoritativeDirectory 1
	#V3AuthVotingInterval 10
	#V3AuthVoteDelay 2
	#V3AuthDistDelay 2

	# hidden services (e.g., ssh and http):
	# NOTE: make sure daemons listen *only* on 127.0.0.1 (not "any")!!!
	#HiddenServiceDir /var/lib/tor/my_hidden_svcs
	#HiddenServicePort 80 127.0.0.1:80
	#HiddenServicePort 22 127.0.0.1:22
EOT

# this will be referenced by the systemd 'topgen-tor-da.service' unit file:
echo "TDA_ADDR='$TDA_ADDR'" > "$TOR_CFG/tda_addr"

# clean up lock file
rm -f "$TOR_CFG/lock"

# add reference to TOR DA into Web vhost front page:
cp -f "$TOR_CFG/torrc" "$TG_VHOST"
TDA_PARA="This is also the simulated $TDA_STR: use <a href=\"torrc\">this configfile</a> for all in-game TOR nodes! </p>"
sed -i "/Below is a list of Web sites/i $TDA_PARA" "$TG_INDEX"

# FIXME: Sort out SELinux policy associated with topgen package !!!
# But, for now, let's label the relevant files and folders manually:
chcon -R -t tor_etc_t "$TOR_CFG"
# also, allow DA binding to ports 5000 and 7000:
setsebool -P tor_bind_all_unreserved_ports 1

echo "Success!!!"
