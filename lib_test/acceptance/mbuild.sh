#!/bin/bash
set -eu

eval `opam config env`
mirage clean
mirage configure --xen
make

