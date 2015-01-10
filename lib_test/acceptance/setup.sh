#!/bin/bash
set -e
set -x

if [ "$USER" != "root" ] ; then
    echo "This script must be run as root!" >&2
    exit 1
fi

. config.sh

#linux_guest_id=`xl domid "$linux_guest_name"`
if xl domid "$linux_guest_name" > /dev/null 2>&1 ; then
    echo "Linux guest $linux_guest_name already exists!" >&2
    exit 1
fi

if brctl show | grep $bridge > /dev/null ; then
    echo "Bridge $bridge already exists!" >&2
    exit 1
fi

# Create a bridge
brctl addbr $bridge
ip link set $bridge address $bridge_mac
ip addr add $bridge_ipaddr/24 dev $bridge
ip link set dev $bridge up

# Start the Linux guest
cat <<EOF > linux-guest.xl
kernel = '${linux_guest_kernel}'
memory = 256
name = '${linux_guest_name}'
#vcpus = 2
serial = 'pty'
disk = [ 'phy:/dev/vg0/linux-guest,xvda,w' ]
vif = ['bridge=${bridge},mac=${linux_guest_mac}' ]
extra = 'console=hvc0 xencons=tty root=/dev/xvda'
EOF
chmod 666 linux-guest.xl

xl create linux-guest.xl

# Wait for it to respond to pings
ping -c 1 -w 60 $linux_guest_ipaddr
