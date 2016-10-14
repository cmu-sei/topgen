#!/bin/bash

# Scrape and curate a corpus of Web sites for TopGen
# (glsomlo@cert.org, December 2015)

# input: original list of sites to scrape:
TOPGEN_ORIG="/etc/topgen/scrape_sites.txt"

# topgen corpus directory structure:
TOPGEN_VARLIB='/var/lib/topgen'

# if "yes", do not print out warnings:
let VERBOSE=0

# recursive scrape depth:
let DEPTH=1

###########################################################################
####    NO FURTHER USER-SERVICEABLE PARTS BEYOND THIS POINT !!!!!!!    ####
###########################################################################

USAGE_BLURB="
Usage: $0 [-s <site_list>] [-t <target_directory>]

The optional command line arguments are:

    -s <site_list>        file containing space or newline separated sites
                          to be scraped for static content; lines beginning
                          with '#' are ignored;
                          (default: $TOPGEN_ORIG).

    -t <target_directory> directory where all results (scraped content, list
                          of vhosts, certificates, configuration files, etc.
                          are stored;
                          (default: $TOPGEN_VARLIB).

    -v                    increase verbosity level (may be used multiple times);
                          (default: $VERBOSE).

Recursively scrape, clean, curate a given list of Web sites. Additionally,
issue certificates signed with a self-signed TopGen CA (which is in turn
also generated, if necessary). Generate a drop-in config file for the nginx
HTTP server, and a hosts file containing <ip_addr fqdn> entries for each
scraped vhost.
" # end usage blurb

# process command line options:
OPTIND=1
while getopts "s:t:vh?" OPT; do
  case "$OPT" in
  s)
    TOPGEN_ORIG=$OPTARG
    ;;
  t)
    TOPGEN_VARLIB=$OPTARG
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
TOPGEN_VARETC="$TOPGEN_VARLIB/etc"
TOPGEN_CERTS="$TOPGEN_VARLIB/certs"
TOPGEN_VHOSTS="$TOPGEN_VARLIB/vhosts"
# topgen.info vhost directory:
TOPGEN_SITE="$TOPGEN_VHOSTS/topgen.info"

# assert existence of required input files and target folders:
[ -s "$TOPGEN_ORIG" -a \
  -d "$TOPGEN_VHOSTS" -a -d "$TOPGEN_VARETC" -a -d "$TOPGEN_CERTS" ] || {
  echo "
ERROR: file \"$TOPGEN_ORIG\" and
       folders \"$TOPGEN_VHOSTS\",
               \"$TOPGEN_VARETC\", and
               \"$TOPGEN_CERTS\" MUST exist
       before running this command!

$USAGE_BLURB
"
  exit 1
}

# assert target folder is empty:
[ -n "$(ls -A $TOPGEN_VHOSTS)" ] && {
  echo "
ERROR: folder \"$TOPGEN_VHOSTS\" MUST be empty
       before running this command!

$USAGE_BLURB
"
  exit 1
}

# default wget options:
WGET_OPTS='-prEHN --convert-file-only --no-check-certificate -e robots=off --random-wait -t 2'
# make wget quiet, unless verbosity >= 2:
((VERBOSE>=2)) || WGET_OPTS="$WGET_OPTS -q"
# make wget print debug output if verbosity >= 3
((VERBOSE>=3)) && WGET_OPTS="$WGET_OPTS -d"

# wget URL list:
WGET_URLS=$(grep -v '^#' "$TOPGEN_ORIG" | \
            tr '[:space:]' ' ' | sed -e 's/[[:space:]]*$/\n/')
[ -n "$WGET_URLS" ] || {
  echo "
ERROR: At least one uncommented URL must be specified
       in \"$TOPGEN_ORIG\" !
"
  exit 1
}

# recursively scrape all sites listed in the $TOPGEN_ORIG file:
wget $WGET_OPTS -U "Mozilla/5.0 (X11)" -l $DEPTH -P $TOPGEN_VHOSTS $WGET_URLS

# wget will likely return some kind of error on a large recursive scrape;
# we are only really interested if it actually segfaults:
[ $? -eq 139 ] && {
  echo "
ERROR: recursive wget scrape encountered a segfault!
"
  exit 1
}

# cleanup; remove IP-only vhosts, and vhosts ending with a ":<port-number>":
shopt -s extglob
rm -rf $TOPGEN_VHOSTS/+([[:digit:].]) $TOPGEN_VHOSTS/*:*

# "curate" remaining vhosts; handle [www.]example.org/index.html issue:
for VH in $TOPGEN_VHOSTS/*; do
  VB=${VH##*/} # basename
  NUM=$(ls $VH | wc -l)
  # if example.org has only one file named "index.html", AND if
  # www.example.org exists and DOESN'T contain "index.html", apply the fix:
  if [ $NUM -eq 1 -a -f "$VH/index.html" -a -d "$TOPGEN_VHOSTS/www.$VB" \
       -a ! -f "$TOPGEN_VHOSTS/www.$VB/index.html" ]; then
    cp "$VH/index.html" "$TOPGEN_VHOSTS/www.$VB/"
    ((VERBOSE)) && echo "curate: $VH/index.html -> $TOPGEN_VHOSTS/www.$VB/"
  fi
done

# topgen.info is reserved, be sure to create it completely from scratch:
rm -rf "$TOPGEN_SITE"
mkdir "$TOPGEN_SITE"

# intersection of scraped vhosts in $TOPGEN_VHOSTS against $TOPGEN_ORIG
comm -12 <(ls -1 $TOPGEN_VHOSTS) \
         <(grep -v '^#' "$TOPGEN_ORIG" | tr '[:space:]' '\n' | \
           sed -e 's|^.*//||; s|/.*$||' | sort -u) \
  > "$TOPGEN_SITE/orig_vhosts.txt"

# generate topgen.info landing page (index.html):
{
  cat <<- "EOT"
	<html>
	  <head>
	    <title>Welcome to TopGen.info !</title>
	  </head>
	  <body> <div style="text-align: justify; width: 500pt">
	    <h2>Welcome to TopGen.info !</h2>
	    This is a simulation of the World Wide Web. View this site in either
	    <ul>
	    <li> Cleartext: <a href="http://topgen.info">http://topgen.info</a>
	    <li> HTTPS: <a href="https://topgen.info">https://topgen.info</a>;
	      <ul>
	      <li> Your browser requires the
	           <a href="topgen_ca.cer">TopGen CA Certificate</a>
	           to avoid certificate warnings! All simulated Web sites are
	           using certificates issued and signed by this CA!
	      </ul>
	    </ul>
	    Below is a list of Web sites mirrored for this simulation:
	    <ul>
	EOT
  for VH in $(< "$TOPGEN_SITE/orig_vhosts.txt"); do
    echo "    <li><a href=\"//$VH\">$VH</a>"
  done
  cat <<- "EOT"
	    </ul>
	  </body>
	</html>
	EOT
} > "$TOPGEN_SITE/index.html"

# NOTE: hand-crafted vhosts should manually be added to $TOPGEN_VHOSTS here!

# generate TopGen CA (unless already provided):
[ -s "$TOPGEN_VARETC/topgen_ca.key" -a -s "$TOPGEN_VARETC/topgen_ca.cer" ] ||
  openssl req -newkey rsa:2048 -nodes -keyout "$TOPGEN_VARETC/topgen_ca.key" \
              -days 7300 -x509 -out "$TOPGEN_VARETC/topgen_ca.cer" \
              -subj '/C=US/ST=PA/L=Pgh/O=CMU/OU=CERT/CN=topgen_ca' \
              2>/dev/null
# ... and place a copy in $TOPGEN_SITE:
cp "$TOPGEN_VARETC/topgen_ca.cer" "$TOPGEN_SITE"

# generate TopGen vhost key (unless already provided):
[ -s "$TOPGEN_VARETC/topgen_vh.key" ] ||
  openssl genrsa -out "$TOPGEN_VARETC/topgen_vh.key" 2048 2>/dev/null

# create CA configuration (file and /tmp directory structure):
TMP_CA_DIR=$(mktemp -d /tmp/TopGenCA.XXXXXXXXXXXXXX)
echo "000a" > "$TMP_CA_DIR/serial" # seed the serial file
touch "$TMP_CA_DIR/index" # empty (but required) index file

# CA configuration file:
TMP_CA_CONF="[ ca ]
default_ca = topgen_ca

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ topgen_ca ]
private_key = $TOPGEN_VARETC/topgen_ca.key
certificate = $TOPGEN_VARETC/topgen_ca.cer
new_certs_dir = $TMP_CA_DIR
database = $TMP_CA_DIR/index
serial = $TMP_CA_DIR/serial
default_days = 3650
default_md = sha512
copy_extensions = copy
unique_subject = no
policy = topgen_ca_policy
x509_extensions = topgen_ca_ext

[ topgen_ca_policy ]
countryName = supplied
stateOrProvinceName = supplied
localityName = supplied
organizationName = supplied
organizationalUnitName = supplied
commonName = supplied
emailAddress = optional

[ topgen_ca_ext ]
basicConstraints = CA:false
nsCertType = server
nsComment = \"TopGen CA Generated Certificate\"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
"

# per-vhost CSR configuration template:
# (NOTE: using [alt_names] to work around CN length limit for long hostnames)
TMP_VH_CONF=$(sed -e '/req_extensions/s/^# //;
                      /^\[ v3_req \]/a subjectAltName = @alt_names' \
                  /etc/pki/tls/openssl.cnf)

# start nginx.conf here (vhost entries to be appended from loop below)
cat > "$TOPGEN_VARETC/nginx.conf" <<- EOT
	# use a common key for all certificates:
	ssl_certificate_key $TOPGEN_VARETC/topgen_vh.key;

	# ensure enumerated https server blocks fit into nginx hash table:
	server_names_hash_bucket_size 256;
	server_names_hash_max_size 131070;
EOT

# nuke hosts.nginx (vhost entries to be appended below):
rm -f "$TOPGEN_VARETC/hosts.nginx"

# process each vhost:
for VH in $TOPGEN_VHOSTS/*; do
  VB=${VH##*/} # basename

  # issue certificate (based on csr generated on-the-fly):
  openssl ca -batch -notext \
          -config <(echo "$TMP_CA_CONF") -out "$TOPGEN_CERTS/$VB.cer" \
          -in <(openssl req -new -key "$TOPGEN_VARETC/topgen_vh.key" \
                        -subj '/C=US/ST=PA/L=Pgh/O=CMU/OU=CERT/CN=topgen_vh' \
                        -config <(echo "$TMP_VH_CONF"
                                  echo -e "[alt_names]\nDNS.1 = $VB") \
                        2>/dev/null) \
          2>/dev/null

  # append vhost https block to nginx.conf file:
  cat >> "$TOPGEN_VARETC/nginx.conf" <<- EOT

	server {
	  listen 80;
	  listen 443 ssl;
	  ssl_certificate $TOPGEN_CERTS/$VB.cer;
	  server_name $VB;
	  root $VH;
	}
	EOT

  # resolve vhost DNS IP address, write to hosts.nginx
  VHIP=$(getent ahostsv4 $VB | head -1 | cut -d' ' -f1)
  # use made-up IP '1.1.1.1' for unresolvable vhosts:
  echo "${VHIP:-'1.1.1.1'} $VB" >> "$TOPGEN_VARETC/hosts.nginx"
done

# done with CA directory:
rm -rf "$TMP_CA_DIR"
