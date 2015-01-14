#!/bin/bash
set -e

eval `opam config env`
cp ../config.ml .
cp ../unikernel.ml .
mirage clean
mirage configure --xen
make

