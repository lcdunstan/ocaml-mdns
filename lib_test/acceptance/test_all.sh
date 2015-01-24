#!/bin/bash
set -eu

. config.sh
. common.sh
need_root

declare -g count_total=0
declare -g count_fail=0

function setup {
    if [ ! -d $tmp_here ] ; then
        mkdir $tmp_here
    fi
    echo -n "Setup: "
    if need_bridge > $tmp_here/setup.out 2>&1 ; then
        echo "OK"
    else
        echo "Failed"
        cat $tmp_here/setup.out
        exit 1
    fi
}

function cleanup {
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
}

function run_test {
    local test_name=$1

    : $(( count_total++ ))
    echo -n "$test_name: "
    if ./${test_name}.sh > $tmp_here/${test_name}.out 2>&1 ; then
        echo "OK"
    else
        echo "Failed (see test_all.err)"
        : $(( count_fail++ ))
        echo "*** Begin $test_name output ***" >> test_all.err
        cat $tmp_here/${test_name}.out >> test_all.err
        echo "*** End $test_name output ***" >> test_all.err
        echo >> test_all.err
        destroy_guests
        delete_bridge
        setup
    fi
}

if [ -f test_all.err ] ; then
    rm test_all.err
fi

cleanup
setup

run_test test_normal_probe
run_test test_conflict_later
run_test test_conflict_simultaneous

echo
echo "*** Summary: ${count_fail} failures out of ${count_total} tests total"

