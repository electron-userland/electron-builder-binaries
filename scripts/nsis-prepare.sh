#!/usr/bin/env bash
set -e

BASEDIR=$(dirname "$0")
cd "$BASEDIR/.."
pwd
cd nsis

rm -rf Docs
rm -rf NSIS.chm
rm -rf Examples
#rm -rf Plugins/x86-ansi
rm -f makensisw.exe

# nsProcess plugin
curl -L http://nsis.sourceforge.net/mediawiki/images/1/18/NsProcess.zip > a.zip
7za x a.zip -oa
unlink a.zip
mv a/Plugin/nsProcessW.dll Plugins/x86-unicode/nsProcess.dll
mv a/Plugin/nsProcess.dll Plugins/x86-ansi/nsProcess.dll
mv a/Include/nsProcess.nsh Include/nsProcess.nsh
rm -rf a

# UAC plugin
curl -L http://nsis.sourceforge.net/mediawiki/images/8/8f/UAC.zip > a.zip
7za x a.zip -oa
mv a/Plugins/x86-unicode/UAC.dll Plugins/x86-unicode/UAC.dll
mv a/Plugins/x86-ansi/UAC.dll Plugins/x86-ansi/UAC.dll
mv a/UAC.nsh Include/UAC.nsh
unlink a.zip
rm -rf a

# WinShell
curl -L http://nsis.sourceforge.net/mediawiki/images/5/54/WinShell.zip > a.zip
7za x a.zip -oa
mv a/Plugins/x86-unicode/WinShell.dll Plugins/x86-unicode/WinShell.dll
mv a/Plugins/x86-ansi/WinShell.dll Plugins/x86-ansi/WinShell.dll
unlink a.zip
rm -rf a

# dir=${PWD##*/}
# rm -rf ../${dir}.7z
# 7za a -m0=lzma2 -mx=9 -mfb=64 -md=64m -ms=on ../${dir}.7z .
