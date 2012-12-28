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

Developer Workstation
=====================

Create a User Account
---------------------
User accounts are managed via htpasswd authentication on the broker machine.
Updating the htpasswd setup for openshift is done by running the htpasswd
command.

```htpasswd /etc/openshift/htpasswd username on the broker.```

Install the RHC Client
----------------------

Instructions on installing rhc for various platforms is available at
 https://openshift.redhat.com/community/developers/install-the-client-tools

In order to use the rhc client with a local openshift installation, it is
necessary to update the LIBRA_SERVER environment variable.

```
export LIBRA_SERVER=broker.example.com
```

Client Tools
============

If you are running RHEL/CentOS, the client tools can be installed and
used for diagnostics against the openshift setup. The configuration steps for
the repo are available below. These are installed by default on the broker
and node machines by the openshift module.

1. Create the following file:

```
/etc/yum.repos.d/openshift-client.repo
```

2. Add the following content:

```
[openshift_client]
name=OpenShift Client
baseurl=https://mirror.openshift.com/pub/origin-server/nightly/enterprise/2012-11-15/Client/x86_64/os/
enabled=1
gpgcheck=0
```

3. Save and close the file.

................................................................................



