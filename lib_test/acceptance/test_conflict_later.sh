#!/bin/bash
set -e

. config.sh
. common.sh
need_root

test_name=test_conflict_later

create_unikernel 0 name-conflict.local
create_unikernel 1 name-conflict.local

start_unikernel 0
echo "Delaying for probe completion..."
sleep 10

start_capture ${test_name}
start_unikernel 1
echo "Delaying for probe with conflict..."
sleep 10
stop_capture ${test_name}
stop_unikernel 0
stop_unikernel 1

dump_capture ${test_name}
./verify_conflict_later.py < $capture_txt > $tmp_here/${test_name}.canon.txt
diff -u expected_conflict_later.txt $tmp_here/${test_name}.canon.txt && echo "No differences"

