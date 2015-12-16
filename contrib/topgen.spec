Name: topgen
Version: 0.0.1
Release: 1%{?dist}
Summary: TopGen Exercise Internet Simulator
License: BSD
Url: http://cert.org
Source0: http://download.cert.org/%{name}-%{version}.tar.xz
Requires(post): systemd-units
Requires(preun): systemd-units
Requires(postun): systemd-units
Requires: coreutils, gawk, grep, sed, openssl, iproute
Requires: bind, nginx, wget >= 1.17.1
BuildRequires: systemd-units
BuildArch: noarch

%description
TopGen provides a simulation of the Internet (Web, DNS, etc.) for
cybersecurity exercise environments.

%prep
%setup -q

%build
echo "nothing to build"

%install
install -d %{buildroot}/%{_unitdir}
install -d %{buildroot}/%{_sbindir}
install -d %{buildroot}/%{_sysconfdir}/nginx/conf.d
install -d %{buildroot}/%{_sysconfdir}/%{name}
install -d %{buildroot}/%{_localstatedir}/lib/%{name}/etc
install -d %{buildroot}/%{_localstatedir}/lib/%{name}/vhosts
install -d %{buildroot}/%{_localstatedir}/lib/%{name}/certs
install -d %{buildroot}/%{_localstatedir}/lib/%{name}/named
%{__ln_s} %{_localstatedir}/lib/%{name}/etc/nginx.conf \
          %{buildroot}%{_sysconfdir}/nginx/conf.d/topgen.conf
install -m 0644 -t %{buildroot}/%{_unitdir} systemd/*
install -m 0755 -t %{buildroot}/%{_sbindir} sbin/*
install -m 0644 -t %{buildroot}/%{_sysconfdir}/%{name} etc/*

%post
%systemd_post topgen-named.service topgen-nginx.service

%preun
%systemd_preun topgen-named.service topgen-nginx.service

%postun
%systemd_postun_with_restart topgen-named.service topgen-nginx.service

%files
%defattr(-,root,root,-)
# miscellaneous doc files and samples:
%doc README LICENSE* TODO contrib
# systemd unit files:
%{_unitdir}/topgen*
# nginx symlink to topgen-specific configuration:
%{_sysconfdir}/nginx/conf.d/topgen.conf
# /etc/topgen directory and config files:
%dir %{_sysconfdir}/%{name}
%config(noreplace) %{_sysconfdir}/%{name}/scrape_sites.txt
%config(noreplace) %{_sysconfdir}/%{name}/delegations.dns
# topgen scripts:
%{_sbindir}/topgen*
# (initially empty) directory structure for storing topgen data:
%dir %{_localstatedir}/lib/%{name}
%dir %{_localstatedir}/lib/%{name}/etc
%dir %{_localstatedir}/lib/%{name}/vhosts
%dir %{_localstatedir}/lib/%{name}/certs
%dir %{_localstatedir}/lib/%{name}/named

%changelog
* Tue Dec 15 2015 Gabriel Somlo <glsomlo at cert.org> 0.0.0.1-1
- initial fedora package
