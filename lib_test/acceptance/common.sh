#!/bin/bash

declare -g last_capture_pid
declare -g capture_txt
#declare -g -a mirage_logcon_array

function flush_cache {
    # Make sure Avahi is not caching old records between tests
    echo "Resetting the bridge"
    ip link set $bridge down
    sleep 1
    ip link set $bridge up
}

function dom_exists {
    local domname=$1
    if xl domid "$domname" > /dev/null 2>&1 ; then
        return 0
    else
        return 1
    fi
}

function wait_dom_stop {
    local domname=$1
    local timeout=$2
    i=0
    while [ $i -lt $timeout ] ; do
        if ! dom_exists "$domname" ; then
            echo
            return 0
        fi
        sleep 1
        echo -n "."
    done
    echo
    return 1
}

function wait_ping {
    local ping_host=$1
    local timeout=$2
    local i=0
    echo "Waiting for ${ping_host}..."
    while [ $i -lt $timeout ] ; do
        if ping -c 1 -w 1 $ping_host > /dev/null ; then
            echo
            return 0
        fi
        echo -n "."
        i=$(( i + 1 ))
    done
    echo
    return 1
}

function need_root {
    if [ "$USER" != "root" ] ; then
        echo "This script must be run as root!" >&2
        exit 1
    fi
}

function chown_user {
    chown $normal_user:$normal_user "$@"
}

function need_bridge {
    if brctl show | grep $bridge > /dev/null ; then
        return 0
    fi

    echo "Creating bridge"
    brctl addbr $bridge
    ip link set $bridge address $bridge_mac
    ip addr add $bridge_ipaddr/24 dev $bridge
    ip link set $bridge up
}

function delete_bridge {
    if brctl show | grep $bridge > /dev/null ; then
        echo "Deleting bridge $bridge"
        ip link set dev $bridge down
        brctl delbr $bridge
    else
        echo "Bridge $bridge doesn't exist"
    fi
}

function create_unikernel {
    local index=$1
    shift
    local dom_cmdline="$*"
    local dom_name=${mirage_name}${index}
    local dom_tmp=$tmp_here/$dom_name
    local dom_kernel=mir-${dom_name}.xen
    local dom_mac=${mirage_mac_array[$index]}
    local dom_ipaddr=${mirage_ipaddr_array[$index]}
    local dom_data=$dom_tmp/data
    local dom_xl=$tmp_here/${dom_name}.xl

    need_bridge
    echo "Building ${dom_name}"
    if [ ! -d $tmp_here ] ; then
        mkdir $tmp_here
    fi
    if [ ! -d $dom_tmp ] ; then
        mkdir $dom_tmp
    fi
    chown_user $dom_tmp
    # Copy test.zone
    if [ ! -d $dom_data ] ; then
        mkdir $dom_data
    fi
    chown_user $dom_data
    cp $mirage_zone_file $dom_data
    # Create config.ml
    cat <<EOF > $dom_tmp/config.ml
open Mirage

let data = crunch "./data"

let my_ipv4_conf =
  let i = Ipaddr.V4.of_string_exn in
  {
    address  = i "${dom_ipaddr}";
    netmask  = i "255.255.255.0";
    gateways = [];
  }

let stack =
  direct_stackv4_with_static_ipv4 default_console tap0 my_ipv4_conf

let main =
  foreign "Unikernel.Main" (console @-> kv_ro @-> stackv4 @-> job)

let () =
  add_to_ocamlfind_libraries [ "mdns.mirage"; "str"; ];
  register "${dom_name}" [ main $ default_console $ data $ stack ]

EOF
    # Copy unikernel.ml
    cp unikernel.ml $dom_tmp/unikernel.ml
    # Build it
    # Requires a separate script for eval `opam config env`
    (cd $dom_tmp && sudo -u $normal_user ../../mbuild.sh > mbuild.log 2>&1)

    # Generate the XL configuration
    cat <<EOF > $dom_xl
name = '${dom_name}'
kernel = '${PWD}/$dom_tmp/${dom_kernel}'
extra = '${dom_cmdline}'
builder = 'linux'
memory = 16
on_crash = 'preserve'

vif = ['bridge=${bridge},mac=${dom_mac}' ]
EOF
    chown_user $dom_xl
}

function start_unikernel {
    for index in "$@" ; do
        local dom_name=${mirage_name}${index}
        local dom_xl=$tmp_here/${dom_name}.xl
        echo "Starting ${dom_name}"
        xl create $dom_xl
    done
    for index in "$@" ; do
        local dom_name=${mirage_name}${index}
        local dom_tmp=$tmp_here/$dom_name
        echo "Logging console to $dom_tmp/console.log"
        ./logcon.py ${dom_name} $dom_tmp/console.log &
        # Looks like we don't need to track the PID of logcon.py
        # because it exits when the domain is destroyed.
        #mirage_logcon_array[$index]=$!
        local dom_ipaddr=${mirage_ipaddr_array[$index]}
        wait_ping $dom_ipaddr 10
    done
}

function stop_unikernel {
    local index=$1
    local dom_name=${mirage_name}${index}

    echo "Destroying ${dom_name}"
    xl destroy $dom_name
}

function create_linux_guest {
    need_bridge

    if [ ! -d $tmp_here ] ; then
        mkdir $tmp_here
    fi
    if xl domid "$linux_guest_name" > /dev/null 2>&1 ; then
        echo "Linux guest $linux_guest_name already exists!" >&2
        exit 1
    fi
    if mount | grep "${linux_guest_snapshot}" > /dev/null ; then
        echo "Unmounting old snapshot"
        umount "/dev/vg0/${linux_guest_snapshot}"
    fi
    if lvs "vg0/${linux_guest_snapshot}" > /dev/null 2>&1 ; then
        echo "Deleting old snapshot"
        lvremove -f "vg0/${linux_guest_snapshot}"
    fi
    lvs "vg0/${linux_guest_lv}" > /dev/null 2>&1 || {
        echo "Linux guest logical volume vg0/${linux_guest_lv} doesn't exist!"
        echo "Create it using build-linux-guest.sh"
        return 1
    }

    echo "Creating volume snapshot..."
    lvcreate --size 100M --snapshot "vg0/${linux_guest_lv}" --name "${linux_guest_snapshot}"
    echo "Mounting the snapshot"
    local tmp_mnt=$tmp_here/mnt
    if [ ! -d $tmp_mnt ] ; then
        mkdir -p $tmp_mnt
    fi
    mount /dev/vg0/${linux_guest_snapshot} $tmp_mnt

    echo "Setting the hostname..."
    echo ${linux_guest_hostname} > $tmp_mnt/etc/hostname

    echo "Configuring the static IP address..."
    cat <<EOF > $tmp_mnt/etc/network/interfaces
auto eth0
iface eth0 inet static
    address ${linux_guest_ipaddr}
    netmask 255.255.255.0
EOF

    echo "Unmounting the snapshot"
    umount $tmp_mnt

    # Generate the Linux guest configuration
    local dom_xl=$tmp_here/linux_guest.xl
    cat <<EOF > $dom_xl
kernel = '${linux_guest_kernel}'
memory = 256
name = '${linux_guest_name}'
#vcpus = 2
serial = 'pty'
disk = [ 'phy:/dev/vg0/${linux_guest_snapshot},xvda,w' ]
vif = ['bridge=${bridge},mac=${linux_guest_mac}' ]
extra = 'console=hvc0 xencons=tty root=/dev/xvda'
EOF
    chown_user $dom_xl
}

function start_linux_guest {
    local dom_xl=$tmp_here/linux_guest.xl

    echo "Starting ${linux_guest_name}"
    xl create $dom_xl
    echo "Logging console to $tmp_here/linux_guest_console.log"
    ./logcon.py ${linux_guest_name} $tmp_here/linux_guest_console.log &
    wait_ping $linux_guest_ipaddr 60
}

function stop_linux_guest {
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

    if mount | grep "${linux_guest_snapshot}" > /dev/null ; then
        echo "Unmounting snapshot"
        umount "/dev/vg0/${linux_guest_snapshot}"
    fi
    if lvs "vg0/${linux_guest_snapshot}" > /dev/null 2>&1 ; then
        echo "Deleting snapshot"
        lvremove -f "vg0/${linux_guest_snapshot}"
    fi
}

function destroy_guests {
    stop_linux_guest
    for index in ${mirage_index_array[*]} ; do
        local dom_name=${mirage_name}${index}
        if dom_exists "$dom_name" ; then
            echo "Destroying: ${dom_name}"
            xl destroy $dom_name
        else
            echo "Nothing to destroy: ${dom_name}"
        fi
    done
}

function start_capture {
    local test_name=$1
    local capture_pcap=$tmp_here/${test_name}.pcap
    if [ -f $capture_pcap ] ; then
        rm $capture_pcap
    fi
    echo "Starting packet capture"
    need_bridge
    tcpdump -q -i $bridge -w $capture_pcap > /dev/null 2>&1 &
    declare -g last_capture_pid=$!
}

function stop_capture {
    local test_name=$1
    local capture_pcap=$tmp_here/${test_name}.pcap
    echo "Stopping packet capture"
    kill -INT $last_capture_pid
    wait $last_capture_pid
    chown_user $capture_pcap
}

function dump_capture {
    local test_name=$1
    local capture_pcap=$tmp_here/${test_name}.pcap
    declare -g capture_txt=$tmp_here/${test_name}.txt
    [ -f "$capture_pcap" ] || echo "Not found: $capture_pcap"
    # Convert the pcap to text
    # -ttttt enables relative timestamps
    # Filter out the ICMP and ARP packets.
    # Filter out the dom0 packets.
    tcpdump -r $capture_pcap -ttttt -vvv udp and not ether host $bridge_mac > $capture_txt 2> /dev/null
    chown_user $capture_txt
}

function verify_hostname {
    local hostname=$1
    local ipaddr=$2
    echo "Verifying that ${hostname} resolve to IP address $ipaddr"
    local expected=`echo -e "${hostname}\t${ipaddr}"`
    local actual=`avahi-resolve-host-name -4 ${hostname} 2>&1`
    if [ "$actual" == "$expected" ] ; then
        return 0
    else
        echo "Mismatch! Actual: $actual"
        return 1
    fi
}

function verify_hostname_error {
    local hostname=$1
    echo "Verifying that ${hostname} fails to resolve"
    local expected="Failed to resolve host name '${hostname}': Timeout reached"
    local actual=`avahi-resolve-host-name -4 ${hostname} 2>&1`
    if [ "$actual" == "$expected" ] ; then
        return 0
    else
        echo "Mismatch! Actual: $actual"
        return 1
    fi
}

# This is required to allow the script to be interrupted
function control_c {
    echo -en "\n*** Interrupted ***\n"
    exit $?
}
trap control_c SIGINT

# Kill background jobs when exiting for any reason
function kill_jobs {
    local job_pids=$(jobs -pr)
    [ -n "$job_pids" ] && kill $job_pids
}
trap kill_jobs EXIT

