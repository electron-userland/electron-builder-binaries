#!/usr/bin/env bash
set -e

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$GITHUB_TOKEN" ] ; then
  SEC=`security find-generic-password -l GH_TOKEN -g 2>&1`
  export GITHUB_TOKEN=`echo "$SEC" | grep "password" | cut -d \" -f 2`
fi

archiveFileName="$NAME-$VERSION.7z"
archiveFile=out/$archiveFileName
rm -f $archiveFile

cd $BASEDIR/$NAME
$BASEDIR/7za a -mx=9 -mfb=64 ../$archiveFile .
cd ..

CHECKSUM=$(shasum -a 512 $archiveFile | xxd -r -p | base64)
$BASEDIR/github-release beyondkmp/electron-builder-binaries $NAME-$VERSION master "Sha512: $CHECKSUM" $archiveFile