provider "aws" {
  region = "eu-west-1"
}

data "aws_vpc" "default-vpc" {
  default = true
}

data "aws_subnets" "default-subnets" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default-vpc.id]
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_s3_bucket" "demo-app-data-bucket" {
  bucket = "demo-app-data-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "demo-app-bucket-acl" {
  bucket = aws_s3_bucket.demo-app-data-bucket.id
  acl = "private"
}

locals {
  first_subnet = data.aws_subnets.default-subnets.ids[0]
  second_subnet = data.aws_subnets.default-subnets.ids[1]
}

module "code-deploy" {
  source = "./code_deploy"
  app-subnets = [local.first_subnet, local.second_subnet]
  elb-subnets = [local.first_subnet, local.second_subnet]
  environment_variables = {
    S3_BUCKET_ARN = aws_s3_bucket.demo-app-data-bucket.arn
  }
  vpc_id = data.aws_vpc.default-vpc.id
  app-name = "demo-app"
  app-image-name = "demo-app-image"
}