#!/bin/bash
set -e

. config.sh
. common.sh
need_root

test_name=test_mirage_start

create_unikernel 0 mirage-mdns

start_capture ${test_name}

start_unikernel 0
echo "Delaying for probe and announce"
sleep 10

stop_capture ${test_name}
stop_unikernel 0

dump_capture ${test_name}
./verify_mirage_start.py < $capture_txt > $tmp_here/verify_mirage_start.txt
diff -u verify_mirage_start.txt $tmp_here/verify_mirage_start.txt && echo "No differences"

