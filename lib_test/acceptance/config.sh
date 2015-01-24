#!/bin/bash

tmp_here=tmp
normal_user=mirage

: ${mac_prefix:=c0:ff:ee:00:00}
: ${ip_prefix:=192.168.3}

bridge=brtest
bridge_mac=${mac_prefix}:01
bridge_ipaddr=${ip_prefix}.1

linux_guest_name=test-linux-guest
linux_guest_hostname=${linux_guest_name}
linux_guest_kernel=/root/dom0_kernel
linux_guest_lv=${linux_guest_name}
linux_guest_mac=${mac_prefix}:02
linux_guest_ipaddr=${ip_prefix}.2

mirage_index_array=(0 1 2)
mirage_zone_file=test.zone
mirage_name=mirage-guest
mirage_mac_array=(${mac_prefix}:03 ${mac_prefix}:04 ${mac_prefix}:05)
mirage_ipaddr_array=(${ip_prefix}.3 ${ip_prefix}.4 ${ip_prefix}.5)
# Convenience only:
mirage_mac=${mirage_mac_array[0]}
mirage_ipaddr=${mirage_ipaddr_array[0]}

if [ -f local-config.sh ] ; then
    . local-config.sh
fi
