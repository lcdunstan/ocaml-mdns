#!/bin/bash

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

function create_unikernel {
    local index=$1
    local dom_hostname=${2-mirage-mdns}
    local dom_name=${mirage_name}${index}
    local dom_tmp=$tmp_here/$dom_name
    local dom_kernel=mir-${dom_name}.xen
    local dom_mac=${mirage_mac_array[$index]}
    local dom_ipaddr=${mirage_ipaddr_array[$index]}
    local dom_data=$dom_tmp/data
    local dom_xl=$tmp_here/${dom_name}.xl

    brctl show | grep $bridge > /dev/null || ./setup.sh

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
  add_to_ocamlfind_libraries [ "mdns.lwt-core"; "str"; ];
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
extra = '${dom_hostname}'
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

function start_capture {
    local test_name=$1
    local capture_pcap=$tmp_here/${test_name}.pcap
    if [ -f $capture_pcap ] ; then
        rm $capture_pcap
    fi
    echo "Starting packet capture"
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
    local ipaddr=$2
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
control_c()
{
    echo -en "\n*** Interrupted ***\n"
    exit $?
}
trap control_c SIGINT

