#!/usr/bin/env bash
set -e

# rm -rf /tmp/nsis && mkdir /tmp/nsis && docker run -ti --rm -v /tmp/nsis:/tmp/nsis buildpack-deps:xenial

# scons 3 leads to error
mkdir -p /tmp/scons && curl -L http://prdownloads.sourceforge.net/scons/scons-local-2.5.1.tar.gz | tar -xz -C /tmp/scons

mkdir -p /tmp/nsis && curl -L https://sourceforge.net/projects/nsis/files/NSIS%203/3.03/nsis-3.03-src.tar.bz2/download | tar -xj -C /tmp/nsis --strip-components 1
cd /tmp/nsis

python /tmp/scons/scons.py STRIP=0 SKIPSTUBS=all SKIPPLUGINS=all SKIPUTILS=all SKIPMISC=all NSIS_CONFIG_CONST_DATA_PATH=no NSIS_MAX_STRLEN=8192 makensis