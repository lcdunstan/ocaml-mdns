#!/bin/bash
set -e

. config.sh
. common.sh

need_root

if brctl show | grep $bridge > /dev/null ; then
    echo "Bridge $bridge already exists!" >&2
    exit 1
fi

# Create a bridge
brctl addbr $bridge
ip link set $bridge address $bridge_mac
ip addr add $bridge_ipaddr/24 dev $bridge
ip link set dev $bridge up
