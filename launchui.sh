#!/usr/bin/env bash
set -e

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$GITHUB_TOKEN" ] ; then
  SEC=`security find-generic-password -l GH_TOKEN -g 2>&1`
  export GITHUB_TOKEN=`echo "$SEC" | grep "password" | cut -d \" -f 2`
fi

tagName="v0.1.4-10.13.0"

stageDir=/tmp/launch-ui-stage
rm -rf "${stageDir}"
mkdir "${stageDir}"

repack()
{
  arch=$1
  platform=$2

  extractDir="${stageDir}/${arch}"
  mkdir "${extractDir}"
  cd "${extractDir}"
  $BASEDIR/7za x ~/Downloads/launchui-v0.1.4-${platform}-${arch}.zip
  $BASEDIR/7za a -m0=lzma2 -mx=9 -mfb=64 -md=256m -ms=on "${stageDir}/launchui-${tagName}-${platform}-${arch}.7z" .
}

#repack "x64" "win32"
#repack "ia32" "win32"
repack "x64" "linux"

#tool-releaser develar/launchui "${tagName}" master "" "${stageDir}/*.7z"