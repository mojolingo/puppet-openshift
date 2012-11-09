class openshift::broker(
  $domain => 'openshift.local',
  $password => 'marionnette',
) {
  package { [bind, bind-utils, mcollective-client, httpd]:
    require => Yumrepo[openshift],
    ensure => present,
  }

  #
  # Named configuration
  #
  exec { "generate named keys":
    command => "dnssec-keygen -a HMAC-MD5 -b 512 -n USER -r /dev/urandom -K /var/named ${domain}",
    unless => "[ -f /var/named/K${domain}*.private ]",
  }

  file { "/etc/rndc.key":
    owner => root, group => named, mode => 0640
  }

  #
  # MCollective configuration
  #
  file { "/etc/mcollective/client.cfg":
    ensure => present,
    content => "
topicprefix = /topic/
main_collective = mcollective
collectives = mcollective
libdir = /usr/libexec/mcollective
logfile = /var/log/mcollective-client.log
loglevel = debug

# Plugins
securityprovider = psk
plugin.psk = unset

connector = stomp
plugin.stomp.host = localhost
plugin.stomp.port = 61613
plugin.stomp.user = mcollective
plugin.stomp.password = ${password}
",
    mode => 0444, owner => root, group => root,
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
