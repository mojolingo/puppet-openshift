class openshift::broker(
  $domain = 'openshift.local',
  $password = 'marionette',
) {

  $keyfile = "/var/named/K${domain}*.key"

  package { [tcl, tk]:
    ensure => present,
  }

  package { "java-1.5.0-gcj":
    ensure => "absent",
  }

  package { [bind, bind-utils, mcollective-client, httpd, policycoreutils, "java-1.6.0-openjdk"]:
    require => [Yumrepo[openshift-infrastructure],
                Package["tcl"],
                Package["tk"],
                Package["java-1.5.0-gcj"],
               ],
    ensure => present,
  }

 #
 # Named configuration
 #
  exec { "generate named keys":
    command => "/usr/sbin/dnssec-keygen -a HMAC-MD5 -b 512 -n USER -r /dev/urandom -K /var/named ${domain}",
    unless => "/usr/bin/[ -f /var/named/K${domain}*.private ]",
    require => Package["bind-utils"],
  }

  service { "named":
    ensure => running,
    require => Exec["named restorecon"],
    subscribe => File["/etc/named.conf"],
    enable => true,
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
    require => [ File["/var/named"],
                 Exec["generate named keys"],
               ],
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
    mode => 0644, owner => apache, group => root,
    require => Package["mcollective-client"],
  }

  # Required OpenShift services
  service { [httpd, network, sshd]:
    ensure => running,
    enable => true,
  }

  lokkit::services { 'openshift' :
    services  => [ 'ssh', 'http', 'https', 'dns' ],
  }

  lokkit::ports { 'openshift' :
    tcpPorts  => [ '61613', '8161' ],
  }

  selinux::boolean { [httpd_unified, httpd_can_network_connect, httpd_can_network_relay, httpd_run_stickshift, named_write_master_zones, allow_ypbind]:
    ensure => on
  }

  exec { "fixfiles rubygem-passenger":
    command => "/sbin/fixfiles -R rubygem-passenger restore",
  }

  exec { "fixfiles mod_passenger":
    command => "/sbin/fixfiles -R mod_passenger restore",
  }

  exec { "boolean restorecon":
    command => "/sbin/restorecon -rv /var/run /usr/share/rubygems/gems/passenger-*",
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

  #########
  # MongoDB
  file { "/etc/mongodb.conf":
    ensure => present,
    path => "/etc/mongodb.conf",
    content => template("openshift/mongodb.conf.erb"),
    owner => root, group => root, mode => 0444,
  }

#  exec { "update zone data":
#    command => "/usr/bin/nsupdate -v -k ${keyfile} <<EOF
#server 127.0.0.1
#update delete ${fqdn} A
#update add ${fqdn} 180 A ${ipaddress}
#show
#send
#quit
#EOF",
#    unless => "/usr/bin/[ ! -f /var/named/K${domain}*.private ]",
#    require => Service["named"],
#  }

  file { "resolv config":
    path => "/etc/resolv.conf",
    content => template("openshift/resolv.conf.broker.erb"),
    owner => root, group => root, mode => 0644,
    require => Service["named"],
  }

  ##########
  # ActiveMQ
  package { activemq:
    require => Yumrepo[openshift-infrastructure],
    ensure => present,
  }

  file { "activemq.xml config":
    path => "/etc/activemq/activemq.xml",
    content => template("openshift/activemq.xml.erb"),
    owner => root, group => root, mode => 0444,
    require => Package["activemq"],
  }

  file { "activemq init script":
    path => "/etc/init.d/activemq",
    content => template("openshift/activemq.init.erb"),
    owner => root, group => root, mode => 0755,
    require => Package["activemq"],
  }

  file { "jetty.xml config":
    path => "/etc/activemq/jetty.xml",
    content => template("openshift/jetty.xml.erb"),
    owner => root, group => root, mode => 0444,
    require => Package["activemq"],
  }

  file { "jetty-realm.properties config":
    path => "/etc/activemq/jetty-realm.properties",
    content => template("openshift/jetty-realm.properties.erb"),
    owner => root, group => root, mode => 0444,
    require => Package["activemq"],
  }

#BROKEN: ACTIVEMQ FAILS TO START PROPERLY
  service { "activemq":
    ensure => running,
    require => [File["activemq init script"],
                File["activemq.xml config"],
                File["jetty.xml config"],
                File["jetty-realm.properties config"],
               ],
    hasstatus => true,
    hasrestart => true,
    enable => true,
  }

  #####################
  # Openshift Framework
  package { [openshift-origin-broker, openshift-origin-broker-util,
             rubygem-openshift-origin-auth-remote-user, rubygem-openshift-origin-msg-broker-mcollective,
             rubygem-openshift-origin-dns-bind]:
    require => [Yumrepo[openshift-infrastructure],
                Service["activemq"],
                Service["named"],
               ],
    ensure => present,
  }

  file { "conf openshift_origin_broker_proxy.conf":
    path => "/etc/httpd/conf.d/000000_openshift_origin_broker_proxy.conf",
    content => template("openshift/openshift-origin-broker_proxy.conf.erb"),
    owner => root, group => root, mode => 0644,
    require => Package["openshift-origin-broker"]
  }

  file { "conf openshift-origin-auth-remote-user.conf":
    path => "/var/www/openshift/broker/httpd/conf.d/openshift-origin-auth-remote-user.conf",
    content => template("openshift/openshift-origin-auth-remote-user.conf.erb"),
    owner => root, group => root, mode => 0644,
    require => Package["openshift-origin-broker"]
  }

  file { "plugin openshift-origin-auth-remote-user.conf":
    path => "/etc/openshift/plugins.d/openshift-origin-auth-remote-user.conf",
    content => template("openshift/openshift-origin-auth-remote-user.conf.plugin.erb"),
    owner => root, group => root, mode => 0644,
    require => Package["rubygem-openshift-origin-auth-remote-user"]
  }

  file { "plugin openshift-origin-msg-broker-mcollective.conf":
    path => "/etc/openshift/plugins.d/openshift-origin-msg-broker-mcollective.conf",
    content => template("openshift/openshift-origin-msg-broker-mcollective.conf.erb"),
    owner => root, group => root, mode => 0644,
    require => Package["rubygem-openshift-origin-msg-broker-mcollective"]
  }

  file { "plugin openshift-origin-dns-bind.conf":
    path => "/etc/openshift/plugins.d/openshift-origin-dns-bind.conf",
    content => template("openshift/openshift-origin-dns-bind.conf.erb"),
    owner => root, group => root, mode => 0644,
    require => Package["rubygem-openshift-origin-dns-bind"]
  }

  file { "openshift htpasswd":
    path => "/etc/openshift/htpasswd",
    content => template("openshift/openshift-htpasswd.erb"),
    owner => root, group => root, mode => 0644,
    require => Package["rubygem-openshift-origin-auth-remote-user"]
  }

  file { "openshift broker.conf":
    path => "/etc/openshift/broker.conf",
    content => template("openshift/openshift-broker.conf.erb"),
    owner => apache, group => apache, mode => 0644,
    require => Package["openshift-origin-broker"]
  }

  exec { "openshift ssl private key":
    command => "/usr/bin/openssl genrsa -out /etc/openshift/server_priv.pem 2048",
    unless => "/usr/bin/[ -f /etc/openshift/server_priv.pem ]",
    require => Package["openshift-origin-broker"],
  }

  exec { "openshift ssl public key":
    command => "/usr/bin/openssl rsa -in /etc/openshift/server_priv.pem -pubout > /etc/openshift/server_pub.pem",
    unless => "/usr/bin/[ -f /etc/openshift/server_pub.pem ]",
    require => Package["openshift-origin-broker"],
  }

  exec { "openshift create mongo user":
    command => "/usr/bin/mongo openshift_broker_dev --eval 'db.addUser(\"openshift\", \"${password}\")'",
    unless => "/bin/echo 'db.system.users.find()' | /usr/bin/mongo openshift_broker_dev | /bin/grep \"\\\"user\\\" : \\\"openshift\\\"\"",
    require => Package["openshift-origin-broker"],
  }

  exec { "openshift create ssh keys":
    command => "/usr/bin/ssh-keygen -t rsa -b 2048 -f /etc/openshift/rsync_id_rsa",
    unless => "/usr/bin/[ -f /etc/openshift/rsync_id_rsa ]",
    require => Package["openshift-origin-broker"],
  }

  exec { "make openshift dns plugin policy":
    command => "/usr/bin/make -f /usr/share/selinux/devel/Makefile",
    cwd  => "/usr/share/selinux/packages/rubygem-openshift-origin-dns-bind",
    unless => "/usr/bin/[ -f /usr/share/selinux/packages/rubygem-openshift-origin-dns-bind/dhcpnamedforward.pp ]",
    require => File["plugin openshift-origin-dns-bind.conf"],
  }

  exec { "enable openshift dns plugin policy":
    command => "/usr/sbin/semodule -i /usr/share/selinux/packages/rubygem-openshift-origin-dns-bind/dhcpnamedforward.pp",
    require => Exec["make openshift dns plugin policy"],
  }

  exec { "run openshift bundler":
    command => "/usr/bin/bundle --local",
    cwd  => "/var/www/openshift/broker",
    unless => "/usr/bin/[ -f /usr/share/selinux/packages/rubygem-openshift-origin-dns-bind/dhcpnamedforward.pp ]",
    require => Exec["enable openshift dns plugin policy"],
  }

  service { "openshift-broker":
    ensure => running,
    require => Exec["run openshift bundler"],
    hasstatus => true,
    hasrestart => true,
    enable => true,
  }

}
