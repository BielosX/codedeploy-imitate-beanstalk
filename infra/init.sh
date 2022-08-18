#!/bin/bash -xe
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
  amazon-linux-extras install epel -y
  yum -y update
  yum -y install nginx
  yum -y install python3
  yum -y install python3-pip
  yum -y install ruby
  yum -y install wget
  yum -y install curl
  yum -y install unzip
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  ./aws/install
  curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh
  pip3 install virtualenv
  TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/placement/region)
  CODE_DEPLOY_URL="https://aws-codedeploy-${REGION}.s3.${REGION}.amazonaws.com/latest/install"
  wget "$CODE_DEPLOY_URL"
  chmod +x ./install
  ./install auto
