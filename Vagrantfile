# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant::Config.run do |config|
  config.vm.box = 'centos63_64min'
  config.vm.box_url = 'https://dl.dropbox.com/u/7225008/Vagrant/CentOS-6.3-x86_64-minimal.box'

  config.vm.define :broker do |broker|
    broker.vm.network :hostonly, "192.168.133.10"

    broker.vm.provision :puppet do |puppet|
        puppet.manifests_path = "manifests"
        puppet.manifest_file  = "broker.pp"
        puppet.options = [
          '--verbose',
          '--debug',
        ]
    end
  end

  config.vm.define :node do |node|
    node.vm.network :hostonly, "192.168.133.20"

    node.vm.provision :puppet do |puppet|
      puppet.manifests_path = "manifests"
      puppet.manifest_file  = "node.pp"
      puppet.options = [
        '--verbose',
        '--debug',
      ]
    end
  end
end
