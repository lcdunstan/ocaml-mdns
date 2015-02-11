#!/bin/bash
set -eu

. config.sh
. common.sh
need_root

test_name=test_normal_probe

flush_cache
create_unikernel 0 -h mirage-mdns.local
start_capture ${test_name}
start_unikernel 0
echo "Delaying for probe and announce"
sleep 10
stop_capture ${test_name}

echo
verify_hostname mirage-mdns.local ${mirage_ipaddr_array[0]}
verify_hostname_error mirage-mdns-bad.local

echo
echo "Querying valid service:"
avahi-browse -t -p _snake._tcp > $tmp_here/sd.txt
diff -u expected_sd.txt $tmp_here/sd.txt && echo "OK"

stop_unikernel 0

echo
echo "Verify packet capture:"
dump_capture ${test_name}
./verify_normal_probe.py < $capture_txt > $tmp_here/${test_name}.canon.txt
diff -u expected_normal_probe.txt $tmp_here/${test_name}.canon.txt && echo "OK"

