#!/bin/bash

amazon-linux-extras install epel -y
yum -y update
yum -y install nginx
yum -y install python3
yum -y install python3-pip
yum -y install ruby
yum -y install wget
yum -y install curl
yum -y install jq
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_IDENTITY=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/dynamic/instance-identity/document)
REGION=$(jq -r '.region' <<< "$INSTANCE_IDENTITY")
INSTANCE_ID=$(jq -r '.instanceId' <<< "$INSTANCE_IDENTITY")

curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh
mkdir -p /usr/lib/systemd/system/fluent-bit.service.d

cat <<EOT > /usr/lib/systemd/system/fluent-bit.service.d/00_env.conf
[Service]
Environment=REGION=${REGION} INSTANCE_ID=${INSTANCE_ID}
EOT

mkdir -p /etc/fluent-bit/fluent-bit.conf.d
cp /tmp/fluent-bit.conf /etc/fluent-bit
systemctl enable fluent-bit
pip3 install virtualenv
pip3 install boto3
CODE_DEPLOY_URL="https://aws-codedeploy-$REGION.s3.$REGION.amazonaws.com/latest/install"
wget "$CODE_DEPLOY_URL"
chmod +x ./install
./install auto