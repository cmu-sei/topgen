# TopGen Overview #
TopGen is a virtualized application service simulator for offline exercise
and training networks. It allows a single host (physical, VM, or container)
to serve multiple co-hosted virtual services (such as multiple HTTP vhosts,
DNS views, and/or SMTP/IMAP virtual mail domains).

## Installation ##
TopGen depends on the following software packages:

        wget (1.17.1 or later)
        nginx
        bind (9)
        postfix, dovecot

Running the './install.sh' script will copy all components of TopGen
to the appropriate locations on the filesystem. Also, see
'./contrib/topgen.spec' for instructions on how to build a TopGen RPM
package.

*FIXME:* Pre-built binary package repositories for various platforms
(Fedora, EPEL, etc.) will be offered in the near future, and will provide
built-in dependency resolution.

*NOTE:* Ensure that your nginx config file ('/etc/nginx/nginx.conf')
includes (a symlink to) '/var/lib/topgen/etc/nginx.conf'. Binary rpm/deb
packages will drop a symlink to the latter file in '/etc/nginx/conf.d/'
and assume that '/etc/nginx/nginx.conf' is preconfigured by default to
include all files from that directory. Also, it is recommended that you
enable "multi_accept on;" in the "events {...}" section of your nginx
config file; this is a recommended best practice which enables nginx to
be more responsive under high load.

## Design ##

### Application Services ###
TopGen consists of several application services capable of offering virtual
multi-hosting at the application level:

        HTTPD: nginx is hosting multiple virtual websites (vhosts)

        DNS: bind9 (named) implements multiple views, selected based on
             the destination IP address used by the client

        SMTP+IMAP: postfix and dovecot are used to implement multiple
                   virtual mail domains

### Network Addressing and Connectivity ###
A large number of host (/32) IP addresses, corresponding to each virtual
application server (each website, nameserver, and mail gateway we simulate)
are then added to the TopGen host's loopback interface. This ensures that
client traffic is delivered to the appropriate application server daemon,
and that replies will originate from the correct source IP address. Routing
infrastructure external to the TopGen host is responsible for directing
all client traffic to TopGen, typically by announcing static default routes
with TopGen's management IP address as the next hop.

## Getting Started ##
After installing the TopGen package and its dependencies, follow this
basic process to set up a TopGen server in standalone (physical or VM)
mode:

### Add Web Content ###
Run

        topgen-scrape.sh

to recursively download content from all websites listed in
'/etc/topgen/scrape_sites.txt', along with all dependencies required
to render them correctly in a browser. At least one site must be listed
(or uncommented) in '/etc/topgen/scrape_sites.txt'. This step requires
network connectivity to the Internet, and, depending on the size and
number of websites to be scraped, might take several *weeks* to complete.
For a relatively quick test, scraping just the content from
'www.wikipedia.org' should only take approximately 15 minutes.

The collected data, along with some generated content (a self-signed
in-game certificate authority, signed certificates for all virtual web
hosts, and an nginx config file snippet) will be located under the
following set of folders:

        /var/lib/topgen/vhosts/*
        /var/lib/topgen/certs/*
        /var/lib/topgen/etc/hosts.nginx
        /var/lib/topgen/etc/hosts.nginx
        /var/lib/topgen/etc/nginx.conf

Alternatively, manually unpack pre-existing content to populate the
above-mentioned destinations.

### Configure Client DNS ###
Ensure the TopGen host uses 8.8.8.8 (and/or 8.8.4.4) as its configured
nameserver(s) in '/etc/resolv.conf'. As long as none of the TopGen
specific services are running and the host has Internet access, it will
use the real public caching nameservers made available by Google. Once
the application service simulator daemons are running, 8.8.8.8 and 8.8.4.4
will be available locally via the loopback interface, and resolve DNS
from the perspective of "fake" Internet as simulated by TopGen. This step
is necessary only for testing by running a client (i.e. web browser)
directly on the TopGen host itself, without the need to involve external
routing infrastructure and dedicated client machines.

### Configure Mail Domains ###
Edit '/etc/topgen/vmail.cfg' and list the name (FQDN), IP address, and
list of accounts to be generated for each virtual email domain. Run

        topgen-vmail.sh

to have the corresponding configuration data placed in
'/var/lib/topgen/etc/[postfix/]' and '/var/lib/topgen/vmail'.

### Configure DNS Service ###
Optionally, edit '/etc/topgen/delegations.dns' to specify second-level
domains and /24 IP networks for which DNS service is to be delegated to
another server in the exercise or simulation, other than TopGen.

Run

        topgen-mkdns.sh

to prepare views for authoritative (root & top-level) and public caching
nameservers. The latter will apply to destination IPs such as 8.8.8.8 and
8.8.4.4, impersonating Google's publicly available caching resolvers.

### Start Services ###
TopGen ships with systemd unit files for each application service type.
To start web and DNS services, run:

        systemctl start topgen-nginx topgen-named

Both of the above have a dependency on 'topgen-loopback', which ensures
that all virtual service IP addresses are added to the TopGen host's
loopback interface.

At this point (provided client DNS was appropriately configured as
specified earlier), open a browser directly on the TopGen host, and
navigate to 'http://topgen.info', which will contain a set of helpful
links for further experimentation. Download and install the CA
certificate, which then allows browsing the available content via HTTPS.

Optionally, to start the virtual mail service, run:

        systemctl start topgen-postfix topgen-dovecot

then use a mail client to send and receive email between the various
available mail domains and accounts. An example '.muttrc' file is
provided in './contrib/muttrc.vmail'.

### Shutdown ###
To shut down all TopGen application services, run:

        systemctl stop topgen-nginx topgen-named \
                       topgen-postfix topgen-dovecot \
                       topgen-loopback

This will stop all service daemons, and remove all secondary IP addresses
from the loopback interface, returning the TopGen host to its default
networking state.
