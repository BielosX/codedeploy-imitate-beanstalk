#!/bin/bash

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
mkdir -p /usr/lib/systemd/system/fluent-bit.service.d

cat <<EOT >> /usr/lib/systemd/system/fluent-bit.service.d/00_region_env.conf
[Service]
Environment=REGION=${REGION}
EOT