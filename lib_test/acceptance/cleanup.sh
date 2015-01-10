#!/bin/bash
set -e

function dom_exists {
    domname=$1
    if xl domid "$domname" 2> /dev/null ; then
        return 0
    else
        return 1
    fi
}

function wait_dom_stop {
    domname=$1
    timeout=$2
    i=0
    while [ $i -lt $timeout ] ; do
        if ! dom_exists "$domname" ; then
            break
        fi
        sleep 1
        echo -n "."
    done
    echo
}

if [ "$USER" != "root" ] ; then
    echo "This script must be run as root!" >&2
    exit 1
fi

. config.sh

# Destroy the Linux guest
if dom_exists "$linux_guest_name" ; then
    echo "Shutting down Linux guest $linux_guest_name"
    xl shutdown "$linux_guest_name"
    echo "Waiting..."
    wait_dom_exit "$linux_guest_name" 20

    echo "Destroying Linux guest $linux_guest_name"
    xl destroy "$linux_guest_name"
    echo "Waiting..."
    wait_dom_stop "$linux_guest_name" 20
else
    echo "Linux guest $linux_guest_name doesn't exist"
fi

# Delete the bridge
if brctl show | grep $bridge > /dev/null ; then
    ip link set dev $bridge down
    brctl delbr $bridge
else
    echo "Bridge $bridge doesn't exist"
fi

