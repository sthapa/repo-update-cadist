Name:      repo-update-cadist
Summary:   repo-update-cadist
Version:   1.0.2
Release:   1%{?dist}
License:   Apache 2.0
Group:     Grid
URL:       https://github.com/opensciencegrid/repo-update-cadist
BuildArch: noarch
Requires: gnupg2
Requires: subversion
Requires: wget
Requires: yum-utils

Source0:   %{name}-%{version}.tar.gz

%description
%{summary}

%prep
%setup

%install
mkdir -p $RPM_BUILD_ROOT%{_bindir}
install -pm 755 %{name}  $RPM_BUILD_ROOT%{_bindir}/
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/cron.d
install -pm 644 %{name}.cron  $RPM_BUILD_ROOT%{_sysconfdir}/cron.d/

%files
%{_bindir}/%{name}
%config(noreplace) %{_sysconfdir}/cron.d/%{name}.cron

%changelog
* Tue Apr 17 2018 Mátyás Selmeci <matyas@cs.wisc.edu> 1.0.2-1
- Fix comment in cron job

* Tue Apr 17 2018 Mátyás Selmeci <matyas@cs.wisc.edu> 1.0.1-1
- Add cron job
- Add dependencies

* Tue Mar 06 2018 Edgar Fajardo <efajardo@physics.ucsd.edu> 1.0.0-2
- Clean and buildroot sections removed

* Mon Mar 05 2018 Edgar Fajardo <efajardo@physics.ucsd.edu> 1.0.0-1
- First RPM 1.0.0 (SOFTWARE-3102)
