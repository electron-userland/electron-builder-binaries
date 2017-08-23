#!/usr/bin/env bash
set -e

NAME=nsis-resources
version=`cat $NAME/version.txt`
archiveFileName=$NAME-$version.7z
archiveFile=out/$archiveFileName
rm -f $archiveFile

cd $NAME
7za a -m0=lzma2 -mx=9 ../$archiveFile .
cd ..

if [ -z "$GITHUB_TOKEN" ] ; then
  SEC=`security find-generic-password -l GH_TOKEN -g 2>&1`
  export GITHUB_TOKEN=`echo "$SEC" | grep "password" | cut -d \" -f 2`
fi

CHECKSUM=$(shasum -a 512 $archiveFile | xxd -r -p | base64)
github-release electron-userland/electron-builder-binaries $NAME-$version master "Sha512: $CHECKSUM" $archiveFile