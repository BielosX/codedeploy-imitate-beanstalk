#!/bin/bash

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_IDENTITY=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/dynamic/instance-identity/document)
REGION=$(jq -r '.region' <<< "$INSTANCE_IDENTITY")
INSTANCE_ID=$(jq -r '.instanceId' <<< "$INSTANCE_IDENTITY")
APP_NAME=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/tags/instance/Name)

cat <<EOT > /etc/fluent-bit/variables.env
REGION=${REGION}
INSTANCE_ID=${INSTANCE_ID}
APP_NAME=${APP_NAME}
EOT
