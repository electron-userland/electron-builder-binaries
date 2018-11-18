#!/usr/bin/env bash
set -e

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$GITHUB_TOKEN" ] ; then
  SEC=`security find-generic-password -l GH_TOKEN -g 2>&1`
  export GITHUB_TOKEN=`echo "$SEC" | grep "password" | cut -d \" -f 2`
fi

tagName="v0.1.4-11.2.0"

stageDir=/tmp/launch-ui-stage
rm -rf "${stageDir}"
mkdir "${stageDir}"

download()
{
  arch=$1
  platform=$2

  jobNameSuffix=$arch
  if [ "$arch" == "ia32" ]; then
     jobNameSuffix=x86
  fi

  curl -L --fail https://ci.appveyor.com/api/projects/develar/launchui/artifacts/packages%2Flaunchui-v0.1.4-win32-${arch}.7z?job=Platform%3A%20${jobNameSuffix} > "${stageDir}/launchui-${tagName}-${platform}-${arch}.7z"
}

download "x64" "win32"
download "ia32" "win32"
#repack "x64" "linux"

tool-releaser develar/launchui "${tagName}" master "" "${stageDir}/*.7z"