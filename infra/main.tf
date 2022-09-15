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

locals {
  app-name = "demo-app"
}

resource "aws_s3_bucket" "demo-app-data-bucket" {
  bucket = "${local.app-name}-data-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "demo-app-bucket-acl" {
  bucket = aws_s3_bucket.demo-app-data-bucket.id
  acl = "private"
}

locals {
  first_subnet = data.aws_subnets.default-subnets.ids[0]
  second_subnet = data.aws_subnets.default-subnets.ids[1]
  region = data.aws_region.current.name
  account_id = data.aws_caller_identity.current.account_id
}

data "aws_iam_policy_document" "ec2-assume-role" {
  version = "2012-10-17"
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "ec2-policy" {
  version = "2012-10-17"
  statement {
    sid = "AllowDownloadBundle"
    effect = "Allow"
    actions = [
      "s3:List*",
      "s3:Get*"
    ]
    resources = ["arn:aws:s3:::${local.app-name}-artifacts-${local.region}-${local.account_id}/*"]
  }
  statement {
    sid = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:TagLogGroup",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/${local.app-name}/*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/${local.app-name}/*:log-stream:*"
    ]
  }
}

resource "aws_iam_role" "app-role" {
  assume_role_policy = data.aws_iam_policy_document.ec2-assume-role.json
  inline_policy {
    name = "${local.app-name}-ec2-policy"
    policy = data.aws_iam_policy_document.ec2-policy.json
  }
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSQSFullAccess"]
}


resource "aws_sqs_queue" "task-queue" {
  visibility_timeout_seconds = 60
}

data "aws_iam_policy_document" "sqs-allow-events" {
  statement {
    effect = "Allow"
    actions = ["sqs:SendMessage"]
    principals {
      identifiers = ["events.amazonaws.com"]
      type = "Service"
    }
    resources = ["*"]
  }
}

resource "aws_sqs_queue_policy" "allow-events" {
  policy = data.aws_iam_policy_document.sqs-allow-events.json
  queue_url = aws_sqs_queue.task-queue.url
}

resource "aws_cloudwatch_event_rule" "schedule-rule" {
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "sqs-event-target" {
  arn = aws_sqs_queue.task-queue.arn
  rule =aws_cloudwatch_event_rule.schedule-rule.name
}

module "code-deploy" {
  source = "./code_deploy"
  app-subnets = [local.first_subnet, local.second_subnet]
  elb-subnets = [local.first_subnet, local.second_subnet]
  environment_variables = {
    S3_BUCKET_ARN = aws_s3_bucket.demo-app-data-bucket.arn,
    QUEUE_URL = aws_sqs_queue.task-queue.url,
    AWS_DEFAULT_REGION = data.aws_region.current.name
  }
  vpc_id = data.aws_vpc.default-vpc.id
  app-name = local.app-name
  app-image-name = "${local.app-name}-image"
  app-health-path = "/health"
  max-instances = 1
  min-instances = 1
  deployment-type = "ALL_AT_ONCE"
  instances-update-policy = "ONE_AT_A_TIME"
  role-id = aws_iam_role.app-role.id
  allow-ssh = true
}