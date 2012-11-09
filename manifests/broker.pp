class openshift::broker(
  $domain => 'openshift.local',
  $password => 'marionnette',
) {
  package { [bind, bind-utils, mcollective-client, httpd, policycoreutils]:
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

  service { "named":
    ensure => running
    require => Exec["named restorecon"],
  }

  exec { "named restorecon":
    command => "/sbin/restorecon -rv /etc/rndc.* /etc/named.* /var/named",
    require => [
      File["/etc/rndc.key"],
      File["/var/named/forwarders.conf"],
      File["/etc/named.conf"],
      File["dynamic zone"],
    ],
  }

  file { "/etc/rndc.key":
    owner => root, group => named, mode => 0640,
    require => Exec["create rndc.key"],
  }

  exec { "create rndc.key":
    command => "/usr/sbin/rndc-confgen -a -r /dev/urandom",
    unless => "[ -f /etc/rndc.key ]",
  }

  file { "/var/named/forwarders.conf":
    owner => root, group => named, mode => 0640,
    content => "forwarders { 8.8.8.8; 8.8.4.4; };\n"
  }

  file { "/var/named":
    ensure => directory,
    owner => named, group => named, mode => 0755,
  }

  file { "/var/named/dynamic":
    ensure => directory,
    owner => named, group => named, mode => 0755
    require => File["/var/named"],
  }

  file { "dynamic zone":
    path => "/var/named/dynamic/${domain}.db",
    content => template("files/dynamic-zone.db.erb"),
    owner => named, group => named, mode => 0644,
    require => File["/var/named"],
  }

  file { "named key":
    path => "/var/named/${domain}.key",
    content => "
key ${domain} {
  algorithm HMAC-MD5;
  secret "${KEY}";
};
",
    owner => named, group => named, mode => 0444,
    require => File["/var/named"],
  }

  file { "/etc/named.conf":
    owner => root, group => named, mode => 0644,
    content => template("named.conf.erb"),
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
