#!/bin/bash
# This script creates a guest partition and bootstraps it with Ubuntu. Must be run as root in dom0 on the host.
# Originally based on instructions from http://openmirage.org/wiki/xen-on-cubieboard2

set -eu
. config.sh
. common.sh
need_root

pvs /dev/mmcblk0p3 > /dev/null 2>&1 || {
    echo "LVM physical volume not found!"
    echo "Use:"
    echo "pvcreate /dev/mmcblk0p3"
    echo "vgcreate vg0 /dev/mmcblk0p3"
    exit 1
}
vgs vg0 > /dev/null 2>&1 || {
    echo "LVM volume group vg0 not found!"
    echo "Use:"
    echo "vgcreate vg0 /dev/mmcblk0p3"
    exit 1
}

echo "Creating guest logical volume..."
lvcreate -L 4G vg0 --name ${linux_guest_lv}
echo "Creating EXT4 file system..."
/sbin/mkfs.ext4 /dev/vg0/${linux_guest_lv}

echo "Bootstrapping..."
mount /dev/vg0/${linux_guest_lv} /mnt && \
trap "umount /mnt" EXIT # umount on exit

debootstrap --arch armhf trusty /mnt

echo "Setting hostname..."
echo ${linux_guest_hostname} > /mnt/etc/hostname

echo "Configuring static IP address..."
cat <<EOF > /mnt/etc/network/interfaces
iface eth0 inet static
    address ${linux_guest_ipaddr}
    netmask 255.255.255.0
EOF

echo "Adding mirage user"
chroot /mnt useradd -s /bin/bash -G sudo -m mirage -p mljnMhCVerQE6	# Password is "mirage"
chroot /mnt passwd root -l # lock root user

echo "Setting up fstab"
echo "/dev/xvda       / ext4   rw,norelatime,nodiratime       0 1" > /mnt/etc/fstab

echo "Installing ssh and avahi..."
chroot /mnt apt-get install -y openssh-server avahi-daemon avahi-utils
echo "UseDNS no" >> /mnt/etc/ssh/sshd_config

echo "Done!"
