#!/bin/bash

echo "Building osslsigncode docker image"
docker build -t electron-builder-binaries/osslsigncode:1.7.1 .

echo "Building osslsigncode binary"
docker run -v `pwd`:/files electron-builder-binaries/osslsigncode:1.7.1