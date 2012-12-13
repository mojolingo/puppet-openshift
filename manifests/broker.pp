class openshift::broker(
  $domain = 'openshift.local',
  $password = 'marionnette'
) {
  package { [bind, bind-utils, mcollective-client, httpd, policycoreutils]:
    require => Yumrepo[openshift],
    ensure => present,
  }

  #
  # Named configuration
  #
  exec { "generate named keys":
    command => "/usr/sbin/dnssec-keygen -a HMAC-MD5 -b 512 -n USER -r /dev/urandom -K /var/named ${domain}",
    unless => "/usr/bin/[ -f /var/named/K${domain}*.private ]",
    require => Package["bind-utils"]
  }

  service { "named":
    ensure => running,
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

  exec { "create rndc.key":
    command => "/usr/sbin/rndc-confgen -a -r /dev/urandom",
    unless => "/usr/bin/[ -f /etc/rndc.key ]",
  }

  file { "/etc/rndc.key":
    owner => root, group => named, mode => 0640,
    require => Exec["create rndc.key"],
  }

  file { "/var/named/forwarders.conf":
    owner => root, group => named, mode => 0640,
    content => "forwarders { 8.8.8.8; 8.8.4.4; };\n"
  }

  file { "/var/named":
    ensure => directory,
    owner => named, group => named, mode => 0755,
    require => Package["bind"]
  }

  file { "/var/named/dynamic":
    ensure => directory,
    owner => named, group => named, mode => 0755,
    require => File["/var/named"],
  }

  file { "dynamic zone":
    path => "/var/named/dynamic/${domain}.db",
    content => template("openshift/dynamic-zone.db.erb"),
    owner => named, group => named, mode => 0644,
    require => File["/var/named"],
  }

  file { "named key":
    path => "/var/named/${domain}.key",
    content => template("openshift/named.key.erb"),
    owner => named, group => named, mode => 0444,
    require => File["/var/named"],
  }

  file { "/etc/named.conf":
    owner => root, group => named, mode => 0644,
    content => template("openshift/named.conf.erb"),
    require => Package["bind"]
  }

  #
  # MCollective configuration
  #
  file { "/etc/mcollective/client.cfg":
    ensure => present,
    content => template("openshift/mcollective-client.cfg.erb"),
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

  define line($file, $line, $ensure = 'present') {
      case $ensure {
          default: { err ( "unknown ensure value ${ensure}" ) }
          present: {
              exec { "/bin/echo '${line}' >> '${file}'":
                  unless => "/bin/grep '${line}' '${file}'"
              }
          }
          absent: {
              exec { "/usr/bin/perl -ni -e 'print unless /^\\Q${line}\\E\$/' '${file}'":
                  onlyif => "/bin/grep '${line}' '${file}'"
              }
          }
      }
  }

  file { "/etc/mongodb.conf": ensure => present, }

  line { "mongodb_auth_val":
    file => "/etc/mongodb.conf",
    line => "auth = true",
  }

  line { "mongodb_smallfiles_val":
    file => "/etc/mongodb.conf",
    line => "smallfiles = true",
  }

}
