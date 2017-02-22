#!/usr/bin/env bash

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

curl http://mirrors.kernel.org/ubuntu/pool/main/liba/libappindicator/libappindicator1_12.10.1+13.10.20130920-0ubuntu4_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libappindicator.so.1.0.0 packages/libappindicator.so.1

# just to be sure

rm -rf ef

curl http://security.ubuntu.com/ubuntu/pool/main/n/nss/libnss3_3.26.2-0ubuntu0.14.04.3_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/ packages/

rm -rf ef

curl http://mirrors.kernel.org/ubuntu/pool/main/libx/libxtst/libxtst6_1.2.2-1_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libXtst.so.6.1.0 packages/libXtst.so.6

rm -rf ef

# required for fedora
curl http://mirrors.kernel.org/ubuntu/pool/main/libx/libxss/libxss1_1.2.2-1_amd64.deb -o f.deb
dpkg-deb -R f.deb ef
mv ef/usr/lib/x86_64-linux-gnu/libXss.so.1.0.0 packages/libXss.so.1