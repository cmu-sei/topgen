#!/bin/bash

# install TopGen
# (glsomlo@cert.org, May 2016)

/bin/echo "Installing using the following filesystem locations:"
/bin/echo "NAME         =${NAME:=topgen};"
/bin/echo "BUILDROOT    =${BUILDROOT:=};"
/bin/echo "UNITDIR      =${UNITDIR:=/usr/lib/systemd/system};"
/bin/echo "SYSCONFDIR   =${SYSCONFDIR:=/etc};"
/bin/echo "LOCALSTATEDIR=${LOCALSTATEDIR:=/var};"
/bin/echo "SBINDIR      =${SBINDIR:=/sbin};"
/bin/echo "MANDIR       =${MANDIR:=/usr/share/man};"

/bin/install -d $BUILDROOT/$UNITDIR
/bin/install -d $BUILDROOT/$SBINDIR
/bin/install -d $BUILDROOT/$MANDIR/man8
/bin/install -d $BUILDROOT/$SYSCONFDIR/nginx/conf.d
/bin/install -d $BUILDROOT/$SYSCONFDIR/$NAME
/bin/install -d $BUILDROOT/$LOCALSTATEDIR/lib/$NAME/etc/postfix
/bin/install -d $BUILDROOT/$LOCALSTATEDIR/lib/$NAME/vhosts
/bin/install -d $BUILDROOT/$LOCALSTATEDIR/lib/$NAME/certs
/bin/install -d $BUILDROOT/$LOCALSTATEDIR/lib/$NAME/named
/bin/install -d $BUILDROOT/$LOCALSTATEDIR/lib/$NAME/vmail
/bin/ln -s $LOCALSTATEDIR/lib/$NAME/etc/nginx.conf \
           $BUILDROOT/$SYSCONFDIR/nginx/conf.d/topgen.conf
/bin/install -m 0644 -t $BUILDROOT/$UNITDIR systemd/*
/bin/install -m 0755 -t $BUILDROOT/$SBINDIR sbin/*
/bin/install -m 0644 -t $BUILDROOT/$MANDIR/man8 man/*
/bin/install -m 0644 -t $BUILDROOT/$SYSCONFDIR/$NAME etc/*
