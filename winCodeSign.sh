#!/usr/bin/env bash

NAME=winCodeSign
version=`cat $NAME/version.txt`
archiveFileName=$NAME-$version.7z
archiveFile=out/$archiveFileName
rm -f $archiveFile

cd $NAME
7za a -m0=lzma2 -mx=9 -mfb=64 -md=64m -ms=on ../$archiveFile .
cd ..

if [ -z "$BT_ACCOUNT" ] ; then
  SEC=`security find-generic-password -l BINTRAY_API_KEY -g 2>&1`
  BT_ACCOUNT=`echo "$SEC" | grep "acct" | cut -d \" -f 4`
  BT_API_KEY=`echo "$SEC" | grep "password" | cut -d \" -f 2`
fi

curl --progress-bar -T $archiveFile -u${BT_ACCOUNT}:${BT_API_KEY} "https://api.bintray.com/content/electron-userland/bin/$NAME/$version/$archiveFileName?override=1&publish=1&list_in_downloads=1" > out/result
result=`cat out/result`
if [ "$result" != '{"message":"success"}' ]; then
  >&2 echo "$result"
  exit 1
fi

echo "sleep 10 seconds to add file to downloads list"

secs=$((10))
while [ $secs -gt 0 ]; do
   echo -ne "$secs\033[0K\r"
   sleep 1
   : $((secs--))
done

curl -u${BT_ACCOUNT}:${BT_API_KEY} -H Content-Type:application/json -X PUT -d '{"list_in_downloads": true}' https://api.bintray.com/file_metadata/electron-userland/bin/$archiveFileName