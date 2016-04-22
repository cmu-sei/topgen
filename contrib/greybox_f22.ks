#
# Fedora GreyBox VM server
# (Gabriel L. Somlo <glsomlo at cert.org>, 2015)
#
text
url --url http://dl.fedoraproject.org/pub/fedora/linux/releases/22/Server/x86_64/os/
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8
firewall --disabled
timezone America/New_York --isUtc
firstboot --disable
xconfig --startxonboot # for core-gui

authconfig --enableshadow --passalgo=sha512

# force default exercise password:
rootpw --plaintext 'tartans@1'

# create user admin (lxdm hates root logins, and core prefers lxde over mate):
user --name='admin' --password='tartans@1'

# set host name (no reverse DNS - install behind NAT):
network --hostname greybox.topgen.info

# services:
services --disabled=abrtd,avahi_daemon

ignoredisk --only-use=vda
bootloader --location=mbr --boot-drive=vda
zerombr
clearpart --all --initlabel --drives=vda

part /boot --fstype=ext4 --recommended
part pv.0 --size=1 --grow
volgroup vg.0 --pesize=4096 pv.0
logvol swap --fstype=swap --name=swap --vgname=vg.0 --recommended
logvol / --fstype=ext4 --name=root --vgname=vg.0 --size=1 --grow


repo --name=Everything --baseurl=http://dl.fedoraproject.org/pub/fedora/linux/releases/22/Everything/x86_64/os/
repo --name=Updates --baseurl=http://dl.fedoraproject.org/pub/fedora/linux/updates/22/x86_64/
# FIXME: replace with official repository before publication (topgen, core-*)
repo --name=GLS --baseurl=http://mirror.ini.cmu.edu/gls/22/x86_64/


%packages
# bare-bones Fedora install:
@core
@standard
@system-tools
expect
inotify-tools
iperf
minicom
sipcalc
wireshark
lynx # web client for text-mode testing
mailx # plaintext mail client for testing
mutt # imamp/smtp client for text-mode testing

# basic graphical lxde desktop (for core-gui):
@base-x # for lxde-desktop (core-gui)
@lxde-desktop # for core-gui
-xpad # brought in by lxde, annoying
-xscreensaver* # brought in by lxde, annoying
dejavu-sans-mono-fonts # for lxde-desktop (core-gui)
firefox # web client for graphics-mode testing

# required (but not explicitly via rpm) by core:
quagga

gls-release # FIXME: move to an official repository before publication
topgen
keepalived # required by topgen/greybox core topology
core-daemon
core-gui
%end


%post

# update packages:
dnf -y update

# fix up 'dir' alias (for root only, not sure system-wide is appropriate):
echo -e "\nalias dir='ls -Alh --color=auto'" >> /root/.bashrc

# fix up how color-ls handles directories (normal color, bold type):
sed -i 's/^DIR.*/DIR 01/' /etc/DIR_COLORS*

# audit craps all over the system log (BZ 1227379)
cat > /etc/rc.d/rc.local <<- "EOT"
	#!/bin/sh

	# F22 audit craps all over system log (BZ 1227379)
	auditctl -e 0
	EOT
chmod 755 /etc/rc.d/rc.local


# remove xscreensaver-* (BZ 1199868, should be fixed in F23)
rpm -e $(rpm -qa | grep xscreensaver)
rpm -e xpad


### TopGen & GreyBox Setup
#


# configure local DNS to use 8.8.8.8 and 8.8.4.4 (either real or in-game)
#

# leave /etc/resolv.conf unmanaged by NetworkManager
sed -i '/^\[main\]/a dns=none' /etc/NetworkManager/NetworkManager.conf
# replace all nameservers in resolv.conf "google cache" addresses:
sed -i '/^nameserver/d' /etc/resolv.conf
cat >> /etc/resolv.conf <<- "EOT"
	nameserver 8.8.4.4
	nameserver 8.8.8.8
	EOT

# mark all network interfaces unmanaged (except the default)
#
DEVICE=${DFLTRT[4]}
for NETDEV in $(ls -1 /sys/class/net | grep -v lo | grep -v $DEVICE); do
	echo 'NM_CONTROLLED=no' >> /etc/sysconfig/network-scripts/ifcfg-$NETDEV
done


# prepare NGINX for TopGen:
#

# global optimizations:
sed -i '/^events {/ r /dev/stdin' /etc/nginx/nginx.conf <<- "EOT"
	    use epoll;
	    multi_accept on;
	EOT

# comment out default server block:
sed -i '/^    server {/,/^    }/s/^/#/' /etc/nginx/nginx.conf


# NOTE: topgen content to be either restored manually or scraped in-place
#        to /var/lib/topgen/...

# auto-start GreyBox CORE topoloy if available:
# (cp /usr/share/doc/topgen/contrib/core_topo/... /etc/topgen/greybox.imn
#  and customize before enabling service)
cat > /etc/systemd/system/greybox.service <<- "EOT"
	[Unit]
	Description=CORE Topology Starter
	ConditionPathExists=/etc/topgen/greybox.imn
	After=core-daemon.service
	# NOTE: "Requires", not just "Wants":
	Requires=core-daemon.service

	[Service]
	Type=oneshot
	RemainAfterExit=yes
	ExecStart=/usr/bin/sh -c "core-gui --batch /etc/topgen/greybox.imn | grep -o 'Session id is [[:digit:]]*' | cut -d' ' -f1-3 --complement > /run/greybox_sess_id"
	ExecStop=/usr/bin/sh -c "core-gui -c $(< /run/greybox_sess_id); rm -f /run/greybox_sess_id"

	[Install]
	WantedBy=multi-user.target
	EOT

%end
