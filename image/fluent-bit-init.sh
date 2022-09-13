#!/bin/bash

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_IDENTITY=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/dynamic/instance-identity/document)
REGION=$(jq -r '.region' <<< "$INSTANCE_IDENTITY")
INSTANCE_ID=$(jq -r '.instanceId' <<< "$INSTANCE_IDENTITY")

mkdir -p /usr/lib/systemd/system/fluent-bit.service.d

cat <<EOT > /usr/lib/systemd/system/fluent-bit.service.d/00_env.conf
[Service]
Environment=REGION=${REGION} INSTANCE_ID=${INSTANCE_ID}
EOT
