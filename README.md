Puppet-OpenShift
================

This Puppet module will assist with the creation of OpenShift nodes.  The configuration
represented here has been taken from the [OpenShift Build-Your-Own PaaS instructions](https://openshift.redhat.com/community/wiki/build-your-own). Note that, like the instructions, this module only works on RHEL/CentOS 6. Tested with CentOS 6.3.


How To Use
==========

An example broker.pp:

```Puppet
include openshift
class { "openshift::broker":
  domain => "example.com",
  password => "badpassword",
}
```

An example node.pp:

```Puppet
include openshift
class { "openshift::node":
  domain => "example.com",
}
```
