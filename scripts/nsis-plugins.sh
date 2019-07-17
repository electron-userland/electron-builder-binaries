#!/usr/bin/env bash
set -ex

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$BASEDIR/../nsis-resources/plugins"

unpack()
{
  curl -L "$1" > a.zip
  7za x a.zip -oa
  unlink a.zip
}

# https://github.com/DigitalMediaServer/NSIS-INetC-plugin/releases
unpack https://github.com/DigitalMediaServer/NSIS-INetC-plugin/releases/download/v1.0.5.6/INetC.zip

for arch in x64-ansi x64-unicode x86-ansi x86-unicode
do
  mv "a/$arch/INetC.dll" "$arch/INetC.dll"
done

rm -rf a

# http://nsis.sourceforge.net/SpiderBanner_plug-in
unpack http://nsis.sourceforge.net/mediawiki/images/4/4c/SpiderBanner_plugin.zip

for arch in x86-ansi x86-unicode
do
  mv "a/Plugins/$arch/SpiderBanner.dll" "$arch/SpiderBanner.dll"
done

# 7z
curl -L https://nsis.sourceforge.io/mediawiki/images/6/69/Nsis7z_19.00.7z > a.7z
7za x a.7z -oa
unlink a.7z
for arch in x64-unicode x86-ansi x86-unicode
do
  mv "a/Plugins/$arch/nsis7z.dll" "$arch/nsis7z.dll"
done

# https://github.com/lordmulder/stdutils/
unpack https://github.com/lordmulder/stdutils/releases/download/1.14/StdUtils.2018-10-27.zip
mv "a/Plugins/Unicode/StdUtils.dll" "x86-unicode/StdUtils.dll"
mv "a/Plugins/ANSI/StdUtils.dll" "x86-ansi/StdUtils.dll"

rm -rf a