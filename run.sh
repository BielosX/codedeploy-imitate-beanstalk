#!/bin/bash

function package() {
  rm -f latest.zip
  zip -r latest.zip requirements.txt
  zip -ur latest.zip nginx.conf
  zip -ur latest.zip appspec.yml
  zip -ur latest.zip fluent-bit.conf
  zip -ur latest.zip src
  zip -ur latest.zip scripts
  zip -ur latest.zip systemd
}

function deploy() {
  ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.Account')
  BUCKET_NAME="demo-app-artifacts-eu-west-1-${ACCOUNT_ID}"
  TIMESTAMP=$(date +%s)
  FILE_NAME="app-${TIMESTAMP}.zip"
  aws s3 cp latest.zip "s3://${BUCKET_NAME}/${FILE_NAME}"
  aws deploy create-deployment --application-name "demo-app" \
    --deployment-group-name "demo-app-deployment-group" \
    --s3-location bucket="${BUCKET_NAME}",bundleType=zip,key="${FILE_NAME}"
}

case "$1" in
  "package") package ;;
  "deploy" ) deploy ;;
  *) echo "package | deploy"
esac