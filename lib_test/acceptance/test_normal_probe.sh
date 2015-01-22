#!/bin/bash
set -e

. config.sh
. common.sh
need_root

which avahi-resolve-host-name >/dev/null || apt-get install avahi-utils -y

test_name=test_normal_probe

create_unikernel 0 mirage-mdns.local
start_capture ${test_name}
start_unikernel 0
echo "Delaying for probe and announce"
sleep 10
stop_capture ${test_name}

echo
echo "Lookup of valid name:"
expected_lookup=`echo -e "mirage-mdns.local\t${mirage_ipaddr_array[0]}"`
echo "Expected: $expected_lookup"
name_lookup=`avahi-resolve-host-name -4 mirage-mdns.local 2>&1`
echo "Actual: $name_lookup"
[ "$name_lookup" = "$expected_lookup" ]

echo
echo "Lookup of invalid name:"
expected_lookup="Failed to resolve host name 'mirage-mdns-bad.local': Timeout reached"
echo "Expected: $expected_lookup"
name_lookup=`avahi-resolve-host-name -4 mirage-mdns-bad.local 2>&1`
echo "Actual: $name_lookup"
[ "$name_lookup" = "$expected_lookup" ]

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

