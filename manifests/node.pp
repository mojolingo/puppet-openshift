class openshift::node(
  $domain = 'openshift.local',
  $gateway = '',
  $password = 'marionnette',
  $broker_rsync_key = '',
  $broker_ipaddress = '',
  $broker_fqdn = '',
) {

  yumrepo { "openshift-node":
    name => "openshift-node",
    baseurl => 'https://mirror.openshift.com/pub/origin-server/nightly/enterprise/2012-11-15/Node/x86_64/os/',
    enabled => 1,
    gpgcheck => 0,
  }

  yumrepo { "openshift-jboss":
    name => "openshift-jboss",
    baseurl => 'https://mirror.openshift.com/pub/origin-server/nightly/enterprise/2012-11-15/JBoss_EAP6_Cartridge/x86_64/os/',
    enabled => 1,
    gpgcheck => 0,
  }

  file { "node resolver":
    path => "/etc/resolv.conf",
    content => template("openshift/resolv.conf.node.erb"),
    owner => root, group => root, mode => 0644,
  }

  file { "/root/.ssh":
    ensure => directory,
    owner => root, group => root, mode => 0700,
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

  file { "node authorized_keys":
    path => "/root/.ssh/authorized_keys",
    ensure => present,
    owner => root, group => root, mode => 0644,
    require => File["/root/.ssh"],
  }

  line { "add broker to authorized keys":
    file => "/root/.ssh/authorized_keys",
    line => "$broker_rsync_key",
  }

  package { [mcollective, openshift-origin-msg-node-mcollective]:
    require => Yumrepo[openshift-infrastructure],
    ensure => present,
  }

  lokkit::services { 'openshift' :
    services  => [ 'ssh', 'http', 'https', 'dns' ],
  }

  # Required OpenShift services
  service { [httpd, network, sshd]:
    ensure => running,
    enable => true,
  }

  file { "dhclient config":
    path => "/etc/dhcp/dhclient-eth0.conf",
    content => template("openshift/dhclient-eth0.conf.erb"),
    ensure => present,
    owner => root, group => root, mode => 0644,
  }

  file { "network sysconfig":
    path => "/etc/sysconfig/network",
    content => template("openshift/sysconfig-network.erb"),
    ensure => present,
    owner => root, group => root, mode => 0644,
  }

  exec { "set hostname":
    command => "/bin/hostname ${fqdn}",
    require => File["network sysconfig"],
  }

  file { "mcollective server config":
    path => "/etc/mcollective/server.cfg",
    content => template("openshift/mcollective-server.cfg.erb"),
    ensure => present,
    owner => root, group => root, mode => 0644,
  }

  service { "mcollective":
    ensure => running,
    require => File["mcollective server config"],
    subscribe => File["mcollective server config"],
    enable => true,
  }

  #Install node rpms
  package { [rubygem-openshift-origin-node, rubygem-passenger-native, openshift-origin-port-proxy, openshift-origin-node-util]:
    require => Yumrepo["openshift-node"],
    ensure => present,
  }

  #Install node cartridges
  package { ["openshift-origin-cartridge-diy-0.1",
             "openshift-origin-cartridge-jenkins-1.4"]:
             "openshift-origin-cartridge-python-2.6",
             "openshift-origin-cartridge-ruby-1.9-scl",
             "openshift-origin-cartridge-cron-1.4",
             "openshift-origin-cartridge-jenkins-client-1.4",
             "openshift-origin-cartridge-mysql-5.1",
             "openshift-origin-cartridge-postgresql-8.4"]:
    require => Yumrepo["openshift-node"],
    ensure => present,
  }

  file { "cgroups config":
    path => "/etc/cgconfig.conf",
    content => template("openshift/cgconfig.conf.erb"),
    ensure => present,
    owner => root, group => root, mode => 0644,
  }

  file { "/cgroup":
    ensure => directory,
    owner => root, group => root, mode => 0755,
  }

  exec { "cgroups restorecon":
    command => "/sbin/restorecon -rv /etc/cgconfig.* /cgroup",
    require => [
      File["/cgroup"],
      File["cgroups config"],
    ],
  }

  service { "cgconfig":
    ensure => running,
    require => Exec["cgroups restorecon"],
    subscribe => File["cgroups config"],
    enable => true,
  }

  service { "cgred":
    ensure => running,
    require => Service["cgconfig"],
    enable => true,
  }

  service { "openshift-cgroups":
    ensure => running,
    require => Service["cgred"],
    enable => true,
  }

  selinux::boolean { [httpd_unified, httpd_can_network_connect,
                      httpd_can_network_relay, httpd_read_user_content,
                      httpd_enable_homedirs, httpd_run_stickshift,
                      allow_polyinstantiation, named_write_master_zones,
                      allow_ypbind]:
    ensure => on
  }

  exec { "fixfiles rubygem-passenger":
    command => "/sbin/fixfiles -R rubygem-passenger restore",
  }

  exec { "fixfiles mod_passenger":
    command => "/sbin/fixfiles -R mod_passenger restore",
  }

  exec { "boolean restorecon":
    command => "/sbin/restorecon -rv /var/run /usr/share/rubygems/gems/passenger-* /usr/sbin/mcollectived /var/log/mcollective.log /var/run/mcollectived.pid /var/lib/openshift /etc/openshift/node.conf /etc/httpd/conf.d/openshift",
  }

  line { "sysctl kernel.sem":
    file => "/etc/sysctl.conf",
    line => "kernel.sem = 250  32000 32  4096",
  }

  line { "sysctl ip_local_port_range":
    file => "/etc/sysctl.conf",
    line => "net.ipv4.ip_local_port_range = 15000 35530",
  }

  line { "sysctl nf_conntrack_max":
    file => "/etc/sysctl.conf",
    line => "net.netfilter.nf_conntrack_max = 1048576",
  }

  exec { "reload sysctl":
    command => "/sbin/sysctl -p /etc/sysctl.conf",
    require => [
                Line["sysctl kernel.sem"],
                Line["sysctl ip_local_port_range"],
                Line["sysctl nf_conntrack_max"],
               ]
  }

  file { "sshd config":
    path => "/etc/ssh/sshd_config",
    content => template("openshift/node-sshd_config.erb"),
    ensure => present,
    owner => root, group => root, mode => 0644,
  }

  lokkit::ports { 'openshift' :
    tcpPorts  => [ '35531-65535' ],
  }

  service { "openshift-port-proxy, openshift-gears":
    ensure => running,
    enable => true,
  }

  file { "openshift node config":
    path => "/etc/openshift/node.conf",
    content => template("openshift/node.conf.erb"),
    ensure => present,
    require => Package["rubygem-openshift-origin-node"],
    owner => root, group => root, mode => 0644,
  }

  exec { "manually initialize openshift facts":
    command => "/etc/cron.minutely/openshift-facts",
    require => File["openshift node config"],
  }

  file { "openshift node pam runuser":
    path => "/etc/pam.d/node-pam.runuser",
    content => template("openshift/node-pam.runuser.erb"),
    ensure => present,
    owner => root, group => root, mode => 0644,
  }

  file { "openshift node pam runuser-l":
    path => "/etc/pam.d/node-pam.runuser-l",
    content => template("openshift/node-pam.runuser-l.erb"),
    ensure => present,
    owner => root, group => root, mode => 0644,
  }

  file { "openshift node pam sshd":
    path => "/etc/pam.d/node-pam.sshd",
    content => template("openshift/node-pam.sshd.erb"),
    ensure => present,
    owner => root, group => root, mode => 0644,
  }

  file { "openshift node pam su":
    path => "/etc/pam.d/node-pam.su",
    content => template("openshift/node-pam.su.erb"),
    ensure => present,
    owner => root, group => root, mode => 0644,
  }

  file { "openshift node pam system-auth-ac":
    path => "/etc/pam.d/node-pam.system-auth-ac",
    content => template("openshift/node-pam.system-auth-ac.erb"),
    ensure => present,
    owner => root, group => root, mode => 0644,
  }

}
