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

remove_images() {
  images=$(aws ec2 describe-images --filters "Name=tag:Name,Values=demo-app-image")
  for k in $(echo "$images" | jq -r '.Images | keys | .[]'); do
    image=$(echo "$images" | jq -r ".Images[$k]")
    image_id=$(echo "$image" | jq -r '.ImageId')
    mapping_keys=$(echo "$image" | jq -r '.BlockDeviceMappings | keys | .[]')
    snapshot_ids=$(echo "$image" | jq -r '.BlockDeviceMappings | map(.Ebs.SnapshotId)')
    echo "Deleting AMI $image_id"
    aws ec2 deregister-image --image-id "$image_id"
    for id in $mapping_keys; do
      snapshot_id=$(echo "$snapshot_ids" | jq -r ".[$id]")
      echo "Deleting snapshot $snapshot_id"
      aws ec2 delete-snapshot --snapshot-id "$snapshot_id"
    done
  done
}

function image() {
  pushd image || exit
  packer build -var "region=eu-west-1" .
  popd || exit
}

case "$1" in
  "image") image ;;
  "remove_images") remove_images ;;
  "package") package ;;
  "deploy" ) deploy ;;
  *) echo "package | deploy | image | remove_images"
esac