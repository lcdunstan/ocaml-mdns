#!/bin/bash
set -e

. config.sh
. common.sh
need_root

test_name=test_conflict_simultaneous

create_unikernel 0 name-conflict
create_unikernel 1 name-conflict

start_capture ${test_name}
start_unikernel 0 1
echo "Delaying for probe with conflict..."
sleep 10
stop_capture ${test_name}
stop_unikernel 0
stop_unikernel 1

dump_capture ${test_name}
./verify_conflict_simultaneous.py ${mirage_ipaddr_array[0]} ${mirage_ipaddr_array[1]} < $capture_txt > $tmp_here/${test_name}.canon.txt
diff -u expected_conflict_simultaneous.txt $tmp_here/${test_name}.canon.txt && echo "No differences"

