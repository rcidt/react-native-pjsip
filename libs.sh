#!/bin/bash
set -e

if ! type "curl" > /dev/null; then 
    echo "Missed curl dependency" >&2; 
    exit 1; 
fi
if ! type "tar" > /dev/null; then 
    echo "Missed tar dependency" >&2; 
    exit 1; 
fi

curl -LO https://github.com/datso/react-native-pjsip-builder/releases/download/v2.7.1-with-vialer/release.tar.gz
tar -xvf release.tar.gz
rm release.tar.gz

curl -LO https://github.com/liveninja/react-native-pjsip/releases/download/1.0.0/VialerPJSIP.zip
unzip VialerPJSIP.zip -d ios/VialerPJSIP.framework || true
rm -rf VialerPJSIP.zip || true
