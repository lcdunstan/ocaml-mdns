#!/bin/bash
# This script creates a guest partition and bootstraps it with Ubuntu. Must be run as root in dom0 on the host.
# Originally based on instructions from http://openmirage.org/wiki/xen-on-cubieboard2

set -eu
. config.sh
. common.sh
need_root

vgs vg0 > /dev/null 2>&1 || {
    echo "LVM volume group vg0 not found!"
    echo "Use:"
    echo "pvcreate /dev/mmcblk0p3"
    echo "vgcreate vg0 /dev/mmcblk0p3"
    exit 1
}
lvs vg0/${linux_guest_lv} > /dev/null 2>&1 && {
    echo "Logical volume vg0/${linux_guest_lv} already exists!"
    echo "Use:"
    echo "lvremove vg0/${linux_guest_lv}"
    exit 1
}

which debootstrap >/dev/null || apt-get install debootstrap -y

echo "Creating guest logical volume..."
lvcreate -L 4G vg0 --name ${linux_guest_lv}
echo "Creating EXT4 file system..."
/sbin/mkfs.ext4 /dev/vg0/${linux_guest_lv}

echo "Bootstrapping..."
mount /dev/vg0/${linux_guest_lv} /mnt && \
trap "umount /mnt" EXIT # umount on exit

machine=`uname -m`
if [ "$machine" == "armv7l" ] ; then
    arch=armhf
elif [ "$machine" == "x86_64" ] ; then
    arch=amd64
else
    echo "Unsupported machine ${machine}"
    exit 1
fi
debootstrap --arch ${arch} trusty /mnt

echo "Setting hostname..."
echo ${linux_guest_hostname} > /mnt/etc/hostname

echo "Configuring DHCP IP address..."
cat <<EOF > /mnt/etc/network/interfaces
auto eth0
iface eth0 inet dhcp
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
