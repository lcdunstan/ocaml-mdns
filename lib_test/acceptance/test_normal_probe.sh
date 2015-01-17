#!/bin/bash
set -e

. config.sh
. common.sh
need_root

test_name=test_normal_probe

create_unikernel 0 mirage-mdns
start_capture ${test_name}
start_unikernel 0
echo "Delaying for probe and announce"
sleep 10
stop_capture ${test_name}
stop_unikernel 0

dump_capture ${test_name}
./verify_normal_probe.py < $capture_txt > $tmp_here/${test_name}.canon.txt
diff -u expected_normal_probe.txt $tmp_here/${test_name}.canon.txt && echo "No differences"

