 virt-install --connect qemu:///system \
--virt-type kvm \
--name windows \
--ram 768 \
--disk path=/var/lib/libvirt/images/windows.img,format=qcow2,bus=virtio \
--vcpus 1 \
--os-type windows \
--os-variant win2k12 \
--network=network=default,model=virtio \
--graphics vnc \
--console pty,target_type=serial \
--disk path=/vagrant/windows.iso,device=cdrom,bus=ide \
--disk path=/vagrant/autounattend.iso,device=cdrom,bus=ide \
--disk path=/vagrant/virtio-win.iso,device=cdrom,bus=ide

