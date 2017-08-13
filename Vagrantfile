# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'digest/md5'
require 'yaml'

ENV['VAGRANT_DEFAULT_PROVIDER'] = 'libvirt'

NETWORKS = {0 => 'vagrant-opennebula-ha-one',
            1 => 'vagrant-opennebula-ha-fs'}

# Read ansible inventory
# https://stackoverflow.com/questions/41094864/is-it-possible-to-write-ansible-hosts-inventory-files-in-yaml
ansible_inventory_file = 'ansible/hosts.yml'
ansible_inventory = YAML::load_file(ansible_inventory_file)

# Base OS configuration scripts
# disable IPv6 on Linux
$linux_disable_ipv6 = <<SCRIPT
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1
SCRIPT
# setenforce 1
$setenforce_1 = <<SCRIPT
if test `getenforce` != 'Enforcing'; then setenforce 1; fi
sed -Ei 's/^SELINUX=.*/SELINUX=Enforcing/' /etc/selinux/config
SCRIPT
# configure a bridge
$ifcfg_bridge = <<SCRIPT
DEVICE=$1
TYPE=$2
BRIDGE=$3
HWADDR=$4
set -x
cat <<END > /etc/sysconfig/network-scripts/ifcfg-$DEVICE
NM_CONTROLLED=yes
BOOTPROTO=none
ONBOOT=yes
DEVICE=$DEVICE
HWADDR=$HWADDR
PEERDNS=no
TYPE=$TYPE
BRIDGE=$BRIDGE
END
ARPCHECK=no /sbin/ifup $DEVICE 2> /dev/null
restorecon -v /etc/sysconfig/network-scripts/ifcfg-$DEVICE
chown root.root /etc/sysconfig/network-scripts/ifcfg-$DEVICE
chmod go+r /etc/sysconfig/network-scripts/ifcfg-$DEVICE
SCRIPT
# configure an interface
$ifcfg = <<SCRIPT
DEVICE=$1
TYPE=$2
IPADDR=$3
NETMASK=$4
set -x
cat <<END > /etc/sysconfig/network-scripts/ifcfg-$DEVICE
NM_CONTROLLED=yes
BOOTPROTO=none
ONBOOT=yes
IPADDR=$IPADDR
NETMASK=$NETMASK
DEVICE=$DEVICE
PEERDNS=no
TYPE=$TYPE
END
ARPCHECK=no /sbin/ifup $DEVICE 2> /dev/null
restorecon -v /etc/sysconfig/network-scripts/ifcfg-$DEVICE
chown root.root /etc/sysconfig/network-scripts/ifcfg-$DEVICE
chmod go+r /etc/sysconfig/network-scripts/ifcfg-$DEVICE
SCRIPT

Vagrant.configure(2) do |config|
  ansible_inventory.keys.sort.each do |group|
    ansible_inventory[group]['hosts'].keys.sort.each do |host|
      # prepare each 'physical' host to be used as both opennebula frontend and node + prepare the mgt server
      if ['mgt', 'one'].include?(group)
        config.vm.define host do |machine|
          machine.vm.box = 'centos/7'
          machine.vm.box_url = machine.vm.box
          machine.vm.hostname = host
          machine.vm.provider 'libvirt' do |p|
            if group == 'mgt'
              p.cpus = 1
              p.memory = 256
            else
              p.cpus = 2
              p.memory = 1536  # 768 used by windows VM
            end
            p.nested = true
            # https://github.com/vagrant-libvirt/vagrant-libvirt: management_network_address defaults to 192.168.121.0/24
            p.management_network_name = 'vagrant-opennebula-ha'
            p.management_network_address = '192.168.122.0/24'
            # https://github.com/vagrant-libvirt/vagrant-libvirt/issues/402
            p.management_network_mode = 'nat'
            # don't prefix VM names with the PWD
            # https://github.com/vagrant-libvirt/vagrant-libvirt/issues/289
            p.default_prefix = ''
            if group == 'one'
              p.storage :file, :size => '25G', :path => host + '_sdb.img', :allow_existing => false, :shareable => false, :type => 'raw'
            end
          end
          # configure additional network interfaces (eth0 is used by Vagrant for management)
          (0..(ansible_inventory[group]['hosts'][host]['ipv4_addresses'].size-1)).to_a.each do |interface|
            libvirt__network_name = NETWORKS[interface]
            ip = ansible_inventory[group]['hosts'][host]['ipv4_addresses'][interface]
            # generate almost unique MAC address for this ip + interface
            mac = '52:54:00:' + Digest::MD5.hexdigest(ip + ':' + interface.to_s).slice(0, 6).scan(/.{1,2}/).join(':')
            # netmask from cidr
            netmask = IPAddr.new('255.255.255.255').mask(24).to_s
            # :auto_config => 'true' configures the specific mac and sets a random ip in the network defined by ip and netmask
            machine.vm.network :private_network, :auto_config => 'false', :libvirt__dhcp_enabled => false,
                               :libvirt__network_name => libvirt__network_name,
                               :ip => ip, :libvirt__netmask => netmask, :mac => mac
          end
          if group == 'one'
            # forward ports from the opennebula bridge interface
            sunstone_port = host.split('.')[0][-1].to_i * 10000 + 9869
            vnc_port = host.split('.')[0][-1].to_i * 10000 + 5900
            machine.vm.network :forwarded_port, adapter: 'eth1', host_ip: '*', guest: 9869, host: sunstone_port
            machine.vm.network :forwarded_port, adapter: 'eth1', host_ip: '*', guest: 5900, host: vnc_port
          end
          # forward sunstone Virtual IP port
          if group == 'mgt'
            machine.vm.network :forwarded_port, adapter: 'eth1', host_ip: '*', guest: 80, host: 10080
          end
          # Base OS configuration
          machine.vm.provision :shell, :inline => 'hostnamectl set-hostname ' + host
          machine.vm.provision :shell, :inline => $linux_disable_ipv6, run: 'always'
          machine.vm.provision :shell, :inline => $setenforce_1
          # http://docs.opennebula.org/5.4/deployment/node_installation/kvm_node_installation.html
          # Step 5. Networking Configuration - setup a linux bridge and include a physical device to the bridge
          if group == 'one'
            machine.vm.provision :shell, :inline => 'ifdown eth1'
            machine.vm.provision 'shell' do |s|
              s.inline = $ifcfg_bridge
              s.args   = ['eth1', 'Ethernet', 'br1',
                          '52:54:00:' + Digest::MD5.hexdigest(
                            ansible_inventory[group]['hosts'][host]['ipv4_addresses'][0] + ':0').slice(0, 6).scan(/.{1,2}/).join(':')]
            end
            machine.vm.provision :shell, :inline => 'yum -y install bridge-utils'
            machine.vm.provision 'shell' do |s|
              s.inline = $ifcfg
              s.args   = ['br1', 'Bridge', ansible_inventory[group]['hosts'][host]['ipv4_addresses'][0], '255.255.255.0']
            end
            machine.vm.provision :shell, :inline => 'ifup eth1'
            machine.vm.provision :shell, :inline => 'ifup br1'
          end
          # MDTMP: todo firewall for landrush
          #machine.vm.provision :shell, :inline => 'if ! `systemctl is-active firewalld > /dev/null`; then systemctl start firewalld; fi'
          #machine.vm.provision :shell, :inline => 'if ! `systemctl is-enabled firewalld > /dev/null`; then systemctl enable firewalld; fi'
          # DNS handled by landrush
          machine.landrush.enabled = true
          machine.landrush.tld = 'mydomain'
          machine.landrush.upstream '8.8.8.8'  # landrush behaves unpredictably, sometimes DNS is not resolving, and 8.8.8.8 is definitely not set in /etc/resolv.conf
          machine.landrush.host_redirect_dns = false
          # configure all ipv4_addresses defined for hosts on the first network interface in DNS
          ansible_inventory.keys.sort.each do |dnsgroup|
            ansible_inventory[dnsgroup]['hosts'].keys.sort.each do |dnshost|
              if (ansible_inventory[dnsgroup]['hosts'][dnshost].is_a? Hash and
                  ansible_inventory[dnsgroup]['hosts'][dnshost].has_key?('ipv4_addresses'))
                dnsipaddress = ansible_inventory[dnsgroup]['hosts'][dnshost]['ipv4_addresses'][0]
                machine.landrush.host dnshost, dnsipaddress
              end
            end
          end
          # sunstone Virtual IP
          config.landrush.host 'sunstone.' + machine.landrush.tld, '192.168.123.10'
          # Install ansible on all machines
          machine.vm.provision :shell, :inline => 'if ! rpm -q epel-release; then yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm; fi'
          # disable yum fastestmirror plugin
          machine.vm.provision :shell, :inline => 'sed -i "s/^enabled=1/enabled=0/" /etc/yum/pluginconf.d/fastestmirror.conf'
          machine.vm.provision :shell, :inline => 'yum -y install ansible'
          # install and enable chrony
          machine.vm.provision :shell, :inline => 'yum -y install chrony'
          machine.vm.provision :shell, :inline => 'systemctl enable chronyd.service'
          machine.vm.provision :shell, :inline => 'systemctl start chronyd.service'
          # Key-based password-less authentication for vagrant user
          machine.vm.provision :file, source: '~/.vagrant.d/insecure_private_key', destination: '~vagrant/.ssh/id_rsa'
          machine.vm.provision :shell, :inline => 'yum -y install wget rsync net-tools tcpdump'  # common tools
          machine.vm.provision :shell, :inline => 'if ! `grep "vagrant insecure public key" ~vagrant/.ssh/authorized_keys > /dev/null`; then wget --no-check-certificate https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub -qO- >> ~vagrant/.ssh/authorized_keys; fi'
        end
      end
    end
  end
  # Once all the machies are provisioned, run ansible from mgt
  # https://www.vagrantup.com/docs/provisioning/ansible.html
  config.vm.define ansible_inventory['mgt']['hosts'].keys.first do |machine|
    # the very first ssh as vagrant user from mgt to all running nodes
    ansible_inventory.keys.sort.each do |sshgroup|
      ansible_inventory[sshgroup]['hosts'].keys.sort.each do |sshhost|
        machine.vm.provision :shell, :inline => 'if `ping -W 1 -c 4 ' + sshhost + ' > /dev/null`; then sudo -u vagrant ssh -o StrictHostKeyChecking=no vagrant@' + sshhost + '; fi'
      end
    end
    if false  # don't run the playbook by vagrant, all steps are explicitly listed in README.md instead
    machine.vm.provision :ansible_local do |ansible|
      ansible.inventory_path = ansible_inventory_file
      ansible.verbose = ''  # 'vvv'
      ansible.limit = 'all'
      ansible.playbook = 'ansible/playbook.yml'
    end
    end
  end
end
