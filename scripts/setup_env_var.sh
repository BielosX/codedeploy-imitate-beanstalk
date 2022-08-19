#!/bin/bash

mkdir -p /etc/app
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
USER_DATA=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/user-data)
echo "$USER_DATA" > /etc/app/00_infra_variables.env
