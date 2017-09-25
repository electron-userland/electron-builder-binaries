#!/usr/bin/env bash

# How do update NSIS:
# 1. Download https://vorboss.dl.sourceforge.net/project/nsis/NSIS%203/3.02.1/nsis-3.02.1.zip (replace 3.02.1 to new version)
# 2. Copy over nsis in this repo and copy nsis-lang-fixes to nsis/Contrib/Language files
# 3. Inspect changed and unversioned files — delete if need.
# 4. brew install makensis --with-large-strings && sudo cp /usr/local/Cellar/makensis/*/bin/makensis nsis/mac/makensis
# 5. See nsis-linux.sh

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

NAME=nsis
version=`cat $NAME/version.txt`
archiveFileName=$NAME-$version.7z
archiveFile=out/$archiveFileName
rm -f $archiveFile

cd $NAME
$BASEDIR/7za a -m0=lzma2 -mx=9 -mfb=64 -md=64m -ms=on ../$archiveFile .
cd ..

if [ -z "$GITHUB_TOKEN" ] ; then
  SEC=`security find-generic-password -l GH_TOKEN -g 2>&1`
  export GITHUB_TOKEN=`echo "$SEC" | grep "password" | cut -d \" -f 2`
fi

CHECKSUM=$(shasum -a 512 $archiveFile | xxd -r -p | base64)
$BASEDIR/github-release electron-userland/electron-builder-binaries $NAME-$version master "Sha512: $CHECKSUM" $archiveFile