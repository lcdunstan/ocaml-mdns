#!/bin/bash
set -e

. config.sh
. common.sh
need_root

declare -g count_total=0
declare -g count_fail=0

function run_test {
    local test_name=$1

    : $(( count_total++ ))
    echo -n "$test_name: "
    if ./${test_name}.sh > $tmp_here/${test_name}.out 2>&1 ; then
        echo "OK"
    else
        echo "Failed"
        : $(( count_fail++ ))
        cat $tmp_here/${test_name}.out
    fi

    # Clear the avahi
}

if [ ! -d $tmp_here ] ; then
    mkdir $tmp_here
fi
echo -n "Cleanup: "
if ./cleanup.sh 2>&1 > $tmp_here/cleanup.out ; then
    echo "OK"
else
    echo "Failed"
    cat $tmp_here/cleanup.out
    exit 1
fi

if [ ! -d $tmp_here ] ; then
    mkdir $tmp_here
fi
echo -n "Setup: "
if ./setup.sh 2>&1 > $tmp_here/setup.out ; then
    echo "OK"
else
    echo "Failed"
    cat $tmp_here/setup.out
    exit 1
fi

run_test test_normal_probe
run_test test_conflict_later
run_test test_conflict_simultaneous

echo
echo "*** Summary: ${count_fail} failures out of ${count_total} tests total"
#./cleanup.sh

