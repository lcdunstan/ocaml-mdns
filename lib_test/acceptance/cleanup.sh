#!/bin/bash
set -eu

. config.sh
. common.sh
need_root

destroy_guests
delete_bridge

rm -rf $tmp_here
