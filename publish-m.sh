#!/usr/bin/env bash
set -ex

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$GITHUB_TOKEN" ] ; then
  SEC=`security find-generic-password -l GH_TOKEN -g 2>&1`
  export GITHUB_TOKEN=`echo "$SEC" | grep "password" | cut -d \" -f 2`
fi

OUT_DIR="$BASEDIR/out/$NAME"
rm -rf "$OUT_DIR"

publish()
{
  CLASSIFIER=$1

  archiveFileName="$NAME-v$VERSION-$CLASSIFIER.7z"
  archiveFile="$OUT_DIR/$archiveFileName"

  cd "$BASEDIR/$NAME/$CLASSIFIER"
  $BASEDIR/7za a -mx=9 -mfb=64 $archiveFile .
  cd ..
}

publish "mac"
publish "linux-x64"
publish "win-ia32"
publish "win-x64"

tool-releaser electron-userland/electron-builder-binaries "$NAME-$VERSION" master "" "$OUT_DIR/*.7z"