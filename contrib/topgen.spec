Name: topgen
Version: 0.0.96
Release: 1%{?dist}
Summary: TopGen: Virtualized Application Service Simulator
License: BSD
Url: http://cert.org
Source0: http://download.cert.org/%{name}-%{version}.tar.xz
Requires(post): systemd-units
Requires(preun): systemd-units
Requires(postun): systemd-units
Requires: coreutils, gawk, grep, sed, openssl, iproute
Requires: bind, nginx, wget >= 1.17.1
Requires: dovecot, postfix
BuildRequires: systemd-units
BuildArch: noarch

%description
TopGen provides a simulation of various Internet application services
(Web, DNS, etc.) for sandboxed cybersecurity exercise environments.

%prep
%setup -q

%build
echo "nothing to build"

%install
NAME=%{name} BUILDROOT=%{buildroot} UNITDIR=%{_unitdir} \
             SYSCONFDIR=%{_sysconfdir} LOCALSTATEDIR=%{_localstatedir} \
             SBINDIR=%{_sbindir} MANDIR=%{_mandir} \
  ./install.sh

%post
%systemd_post topgen-named.service topgen-nginx.service topgen-postfix.service topgen-dovecot.service

%preun
%systemd_preun topgen-named.service topgen-nginx.service topgen-postfix.service topgen-dovecot.service

%postun
%systemd_postun_with_restart topgen-named.service topgen-nginx.service topgen-postfix.service topgen-dovecot.service

%files
%defattr(-,root,root,-)
# miscellaneous doc files and samples:
%doc README.md LICENSE* TODO contrib
# systemd unit files:
%{_unitdir}/topgen*
# nginx symlink to topgen-specific configuration:
%{_sysconfdir}/nginx/conf.d/topgen.conf
# /etc/topgen directory and config files:
%dir %{_sysconfdir}/%{name}
%config(noreplace) %{_sysconfdir}/%{name}/scrape_sites.txt
%config(noreplace) %{_sysconfdir}/%{name}/delegations.dns
%config(noreplace) %{_sysconfdir}/%{name}/vmail.cfg
# executables:
%{_sbindir}/topgen*
# manpages:
%{_mandir}/man*/*
# (initially empty) directory structure for storing topgen data:
%dir %{_localstatedir}/lib/%{name}
%dir %{_localstatedir}/lib/%{name}/etc
%dir %{_localstatedir}/lib/%{name}/etc/postfix
%dir %{_localstatedir}/lib/%{name}/vhosts
%dir %{_localstatedir}/lib/%{name}/certs
%dir %{_localstatedir}/lib/%{name}/named
%dir %attr (0700, dovenull, dovenull) %{_localstatedir}/lib/%{name}/vmail

%changelog
* Thu May 26 2016 Gabriel Somlo <glsomlo at cert.org> 0.1.0-1
- updated to 0.1.0

* Thu Mar 03 2016 Gabriel Somlo <glsomlo at cert.org> 0.0.2-1
- updated to 0.0.2 (with support for virtual email services)

* Tue Dec 15 2015 Gabriel Somlo <glsomlo at cert.org> 0.0.1-1
- initial fedora package
