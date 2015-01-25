#!/bin/bash
set -eu

. config.sh
. common.sh
need_root

test_name=test_conflict_avahi

flush_cache
create_unikernel 0 -h ${linux_guest_hostname}.local
create_linux_guest

# In the first phase, the Linux guest is started first
start_linux_guest
echo "Delaying for probe completion..."
sleep 10

start_capture ${test_name}-1
start_unikernel 0
echo "Delaying for probe with conflict..."
sleep 10
stop_capture ${test_name}-1

# The Linux guest wins because it probed first
verify_hostname ${linux_guest_hostname}.local ${linux_guest_ipaddr}
verify_hostname ${linux_guest_hostname}2.local ${mirage_ipaddr_array[0]}

stop_unikernel 0
stop_linux_guest

dump_capture ${test_name}-1
#./verify_conflict_later.py < $capture_txt > $tmp_here/${test_name}.canon.txt
#diff -u expected_conflict_later.txt $tmp_here/${test_name}.canon.txt && echo "No differences"

