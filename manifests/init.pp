class openshift(
  $openshift_domain = 'openshift.local',
) {
  include lokkit::clear

  class { ntp:
    ensure     => running,
    servers    => [ "time.apple.com iburst",
                    "pool.ntp.org iburst",
                    "clock.redhat.com iburst"],
    autoupdate => true,
  }

  yumrepo { "openshift":
    baseurl => 'https://mirror.openshift.com/pub/origin-server/nightly/enterprise/2012-10-18/Infrastructure/x86_64/os/',
    enabled => 1,
    gpgcheck => 0,
  }

  package { [bind, bind-utils]:
    require => Yumrepo[openshift],
    ensure => present,
  }

  # Required OpenShift services
  service { [httpd, network, sshd]:
    ensure => running,
  }

  lokkit::services { 'openshift' :
    services  => [ 'ssh', 'http', 'https' ],
  }

  selinux::boolean { [httpd_unified, httpd_can_network_connect, httpd_can_network_relay, httpd_run_stickshift, named_write_master_zones, allow_ypbind]:
    ensure => on
  }

}
