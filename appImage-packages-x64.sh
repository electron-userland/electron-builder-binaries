#!/usr/bin/env bash
set -e

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

rm -rf /tmp/appimage
mkdir /tmp/appimage
cd /tmp/appimage

mkdir packages

# required for ElementaryOS

curl http://mirrors.kernel.org/ubuntu/pool/main/g/gconf/libgconf-2-4_3.2.6-0ubuntu2_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libgconf-2.so.4.1.5 packages/libgconf-2.so.4

rm -rf ef

curl http://mirrors.kernel.org/ubuntu/pool/main/libn/libnotify/libnotify4_0.7.6-1ubuntu3_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libnotify.so.4.0.0 packages/libnotify.so.4

rm -rf ef

# libappindicator1
curl http://mirrors.kernel.org/ubuntu/pool/main/liba/libappindicator/libappindicator1_12.10.1+13.10.20130920-0ubuntu4_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libappindicator.so.1.0.0 packages/libappindicator.so.1

curl http://mirrors.kernel.org/ubuntu/pool/main/libi/libindicator/libindicator7_12.10.2+14.04.20140402-0ubuntu1_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libindicator.so.7.0.0 packages/libindicator.so.7

rm -rf ef

# libxtst6
curl http://mirrors.kernel.org/ubuntu/pool/main/libx/libxtst/libxtst6_1.2.2-1_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libXtst.so.6.1.0 packages/libXtst.so.6

rm -rf ef

# libxss1, required for fedora
curl http://mirrors.kernel.org/ubuntu/pool/main/libx/libxss/libxss1_1.2.2-1_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libXss.so.1.0.0 packages/libXss.so.1

cp /tmp/appimage/packages/* $BASEDIR/x86_64-linux-gnu/