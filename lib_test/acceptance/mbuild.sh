#!/bin/bash
set -e

eval `opam config env`
mirage clean
mirage configure --xen
make

