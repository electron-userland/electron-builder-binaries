#!/usr/bin/env bash
set -ex

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
OUTPUT_DIR=$BASEDIR/nsis/windows

TMP_DIR=/tmp/nsis-windows
rm -rf $TMP_DIR
mkdir -p $TMP_DIR

VERSION=3.11

# Download the latest version of NSIS (Windows)
curl -L https://sourceforge.net/projects/nsis/files/NSIS%203/$VERSION/nsis-$VERSION.zip/download > nsis.zip
unzip -o nsis.zip -d nsis-$VERSION
cp -a nsis-$VERSION/nsis-$VERSION/* $TMP_DIR/
rm -rf nsis.zip nsis-$VERSION

curl -L https://sourceforge.net/projects/nsis/files/NSIS%203/$VERSION/nsis-$VERSION-strlen_8192.zip/download > nsis-strlen_8192.zip
unzip -o nsis-strlen_8192.zip -d nsis-strlen_8192
cp -a nsis-strlen_8192/* $TMP_DIR/
rm -rf nsis-strlen_8192.zip nsis-strlen_8192

# cleanup untracked files
rm $TMP_DIR/Bin/GenPat.exe
rm $TMP_DIR/Bin/MakeLangId.exe
rm $TMP_DIR/Bin/RegTool-x86.bin
rm $TMP_DIR/Bin/zip2exe.exe
rm -rf $TMP_DIR/Docs/
rm -rf $TMP_DIR/Examples/
# rm $TMP_DIR/Include/Integration.nsh
# rm $TMP_DIR/Include/Win/RestartManager.nsh
rm $TMP_DIR/NSIS.chm
rm $TMP_DIR/makensisw.exe

# Copy over the "fixed" language files (are these still needed?)
cp -a $BASEDIR/packages/nsis-lang-fixes/* $TMP_DIR/Contrib/Language\ files/

# nsProcess plugin
curl -L http://nsis.sourceforge.net/mediawiki/images/1/18/NsProcess.zip > a.zip
7za x a.zip -oa
mv a/Plugin/nsProcessW.dll $TMP_DIR/Plugins/x86-unicode/nsProcess.dll
mv a/Plugin/nsProcess.dll $TMP_DIR/Plugins/x86-ansi/nsProcess.dll
mv a/Include/nsProcess.nsh $TMP_DIR/Include/nsProcess.nsh
rm -rf a a.zip

# UAC plugin
curl -L http://nsis.sourceforge.net/mediawiki/images/8/8f/UAC.zip > a.zip
7za x a.zip -oa
mv a/Plugins/x86-unicode/UAC.dll $TMP_DIR/Plugins/x86-unicode/UAC.dll
mv a/Plugins/x86-ansi/UAC.dll $TMP_DIR/Plugins/x86-ansi/UAC.dll
mv a/UAC.nsh $TMP_DIR/Include/UAC.nsh
rm -rf a a.zip

# WinShell
curl -L http://nsis.sourceforge.net/mediawiki/images/5/54/WinShell.zip > a.zip
7za x a.zip -oa
mv a/Plugins/x86-unicode/WinShell.dll $TMP_DIR/Plugins/x86-unicode/WinShell.dll
mv a/Plugins/x86-ansi/WinShell.dll $TMP_DIR/Plugins/x86-ansi/WinShell.dll
rm -rf a a.zip

echo $VERSION > $TMP_DIR/VERSION
mkdir -p $OUTPUT_DIR
cp -a $TMP_DIR/* $OUTPUT_DIR