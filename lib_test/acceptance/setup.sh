#!/bin/bash
set -e

. config.sh
. common.sh

need_root

if brctl show | grep $bridge > /dev/null ; then
    echo "Bridge $bridge already exists!" >&2
    exit 1
fi

echo "Creating bridge"
brctl addbr $bridge
ip link set $bridge address $bridge_mac
ip addr add $bridge_ipaddr/24 dev $bridge
ip link set dev $bridge up

echo "Wait for dom0 to finish mDNS probe/announce"
tcpdump -q -i $bridge &
cap_pid=$!
sleep 10
kill -INT $cap_pid
wait $cap_pid
