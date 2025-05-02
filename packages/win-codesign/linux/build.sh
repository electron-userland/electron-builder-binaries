#!/bin/bash -ex

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $BASEDIR
echo "Building osslsigncode docker image"
docker build -t electron-builder-binaries/osslsigncode:2.9 .

echo "Building osslsigncode binary"
docker run -v `pwd`:/files electron-builder-binaries/osslsigncode:2.9