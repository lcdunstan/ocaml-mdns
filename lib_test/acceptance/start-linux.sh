#!/bin/bash
set -e

. config.sh
. common.sh

need_root

if xl domid "$linux_guest_name" > /dev/null 2>&1 ; then
    echo "Linux guest $linux_guest_name already exists!" >&2
    exit 1
fi

# Generate the Linux guest configuration
if [ ! -d $tmp_here ] ; then
    mkdir $tmp_here
fi
linux_guest_xl=$tmp_here/linux_guest.xl
cat <<EOF > $linux_guest_xl
kernel = '${linux_guest_kernel}'
memory = 256
name = '${linux_guest_name}'
#vcpus = 2
serial = 'pty'
disk = [ 'phy:${linux_guest_disk},xvda,w' ]
vif = ['bridge=${bridge},mac=${linux_guest_mac}' ]
extra = 'console=hvc0 xencons=tty root=/dev/xvda'
EOF
chown $normal_user:$normal_user $linux_guest_xl

# Start the Linux guest
xl create $linux_guest_xl

# Wait for it to respond to pings
wait_ping $linux_guest_ipaddr 60
