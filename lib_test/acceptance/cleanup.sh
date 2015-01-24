#!/bin/bash
set -eu

. config.sh
. common.sh
need_root

# Destroy the guests
if dom_exists "$linux_guest_name" ; then
    echo "Shutting down Linux guest $linux_guest_name"
    xl shutdown "$linux_guest_name"
    echo "Waiting..."
    if ! wait_dom_stop "$linux_guest_name" 20 ; then
        echo "Destroying Linux guest $linux_guest_name"
        xl destroy "$linux_guest_name"
        echo "Waiting..."
        wait_dom_stop "$linux_guest_name" 20
    fi
else
    echo "Linux guest $linux_guest_name doesn't exist; nothing to destroy"
fi

for index in ${mirage_index_array[*]} ; do
    dom_name=${mirage_name}${index}
    if dom_exists "$dom_name" ; then
        echo "Destroying: ${dom_name}"
        xl destroy $dom_name
    else
        echo "Nothing to destroy: ${dom_name}"
    fi
done

# Delete the bridge
if brctl show | grep $bridge > /dev/null ; then
    echo "Deleting bridge $bridge"
    ip link set dev $bridge down
    brctl delbr $bridge
else
    echo "Bridge $bridge doesn't exist"
fi

rm -rf $tmp_here
