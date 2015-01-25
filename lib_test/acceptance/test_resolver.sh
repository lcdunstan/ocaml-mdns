#!/bin/bash
set -eu

. config.sh
. common.sh
need_root

test_name=test_resolver
dom0_hostname=`hostname`

create_unikernel 0 -h mirage-mdns.local
create_unikernel 1 -r mirage-mdns.local -r ${dom0_hostname}.local
start_capture ${test_name}
start_unikernel 0
echo "Delaying for probe and announce"
sleep 10

start_unikernel 1
echo "Delaying for resolver"
sleep 10
stop_capture ${test_name}

stop_unikernel 0
stop_unikernel 1

dump_capture ${test_name}
if grep "Success: gethostbyname mirage-mdns.local => ${mirage_ipaddr_array[0]}" < $tmp_here/${mirage_name}1/console.log; then
    echo "OK"
else
    echo "Unikernel resolver: failed (see console.log)"
    exit 1
fi
if grep "Success: gethostbyname ${dom0_hostname}.local => ${bridge_ipaddr}" < $tmp_here/${mirage_name}1/console.log; then
    echo "OK"
else
    echo "Unikernel resolver: failed (see console.log)"
    exit 1
fi

