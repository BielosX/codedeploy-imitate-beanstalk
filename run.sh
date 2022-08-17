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
  TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --names "demo-app-target-group" | jq -r '.TargetGroups[0].TargetGroupArn')
  aws s3 cp latest.zip "s3://${BUCKET_NAME}/${FILE_NAME}"
  python deploy.py --application "demo-app" \
    --deployment-group "demo-app-deployment-group" \
    --bucket "${BUCKET_NAME}" \
    --bucket-key "${FILE_NAME}" \
    --target-group-arn "${TARGET_GROUP_ARN}"

}

case "$1" in
  "package") package ;;
  "deploy" ) deploy ;;
  *) echo "package | deploy"
esac