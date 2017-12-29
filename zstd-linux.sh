#!/usr/bin/env bash
set -e

# rm -rf /tmp/zstd && mkdir /tmp/zstd && docker run -ti --rm -v /tmp/zstd:/tmp/zstd buildpack-deps:xenial


git clone https://github.com/facebook/zstd.git
cd zstd
make -j9 install
cp /usr/local/bin/zstd /tmp/zstd/zstd
