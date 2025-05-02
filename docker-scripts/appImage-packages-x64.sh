#!/usr/bin/env bash
set -ex

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
OUTPUT_DIR=$BASEDIR/appimage
mkdir -p $OUTPUT_DIR

TMP_DIR=/tmp/appimage-packages-x64
rm -rf $TMP_DIR
mkdir $TMP_DIR
cd $TMP_DIR

mkdir packages

# required for ElementaryOS

curl https://old-releases.ubuntu.com/ubuntu/pool/main/g/gconf/libgconf-2-4_3.2.6-0ubuntu1_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libgconf-2.so.4.1.5 packages/libgconf-2.so.4

rm -rf ef

curl http://old-releases.ubuntu.com/ubuntu/pool/main/libn/libnotify/libnotify4_0.7.6-1ubuntu3_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libnotify.so.4.0.0 packages/libnotify.so.4

rm -rf ef

# libappindicator1
curl http://old-releases.ubuntu.com/ubuntu/pool/main/liba/libappindicator/libappindicator1_12.10.1+13.10.20130920-0ubuntu4_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libappindicator.so.1.0.0 packages/libappindicator.so.1

rm -rf ef

# libindicator7
curl https://old-releases.ubuntu.com/ubuntu/pool/main/libi/libindicator/libindicator7_12.10.2+14.10.20140922-0ubuntu1_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libindicator.so.7.0.0 packages/libindicator.so.7

rm -rf ef

# libxtst6
curl http://old-releases.ubuntu.com/ubuntu/pool/main/libx/libxtst/libxtst6_1.2.2-1_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libXtst.so.6.1.0 packages/libXtst.so.6

rm -rf ef

# libxss1, required for fedora
curl http://old-releases.ubuntu.com/ubuntu/pool/main/libx/libxss/libxss1_1.2.2-1_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libXss.so.1.0.0 packages/libXss.so.1

rm -rf ef

rm -rf $OUTPUT_DIR
mkdir $OUTPUT_DIR
cp -a $TMP_DIR/packages/* $OUTPUT_DIR