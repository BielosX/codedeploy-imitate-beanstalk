provider "aws" {
  region = "eu-west-1"
}

data "aws_ami" "amazon-linux-2" {
  owners = ["amazon"]
  most_recent = true
  filter {
    name = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  filter {
    name = "root-device-type"
    values = ["ebs"]
  }
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

locals {
  nginx-port = 8080
  lb-listener-port = 80
  app-health-path = "/health"
  first-subnet = data.aws_subnets.default-subnets.ids[0]
  second-subnet = data.aws_subnets.default-subnets.ids[1]
}

resource "aws_s3_bucket" "deployment-bucket" {
  bucket = "demo-app-artifacts-eu-west-1-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "deployment-bucket-acl" {
  bucket = aws_s3_bucket.deployment-bucket.id
  acl = "private"
}

resource "aws_security_group" "lb-security-group" {
  vpc_id = data.aws_vpc.default-vpc.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = local.lb-listener-port
    to_port = local.lb-listener-port
    protocol = "tcp"
  }
  egress {
    cidr_blocks = [data.aws_vpc.default-vpc.cidr_block]
    from_port = local.nginx-port
    to_port = local.nginx-port
    protocol = "tcp"
  }
}

resource "aws_security_group" "demo-instance-security-group" {
  vpc_id = data.aws_vpc.default-vpc.id
  ingress {
    security_groups = [aws_security_group.lb-security-group.id]
    from_port = local.nginx-port
    to_port = local.nginx-port
    protocol = "tcp"
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 22
    to_port = 22
    protocol = "tcp"
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 443
    to_port = 443
    protocol = "tcp"
  }
}

resource "aws_lb" "demo-app-lb" {
  name = "demo-app-lb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.lb-security-group.id]
  subnets = [local.first-subnet, local.second-subnet]
}

resource "aws_lb_target_group" "demo-app-target-group" {
  name = "demo-app-target-group"
  protocol = "HTTP"
  port = local.nginx-port
  vpc_id = data.aws_vpc.default-vpc.id
  health_check {
    enabled = true
    matcher = "200"
    path = local.app-health-path
  }
}

resource "aws_alb_listener" "default-listener" {
  load_balancer_arn = aws_lb.demo-app-lb.arn
  protocol = "HTTP"
  port = 80
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.demo-app-target-group.arn
  }
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

data "aws_iam_policy_document" "code-deploy-assume-role" {
  version = "2012-10-17"
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["codedeploy.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "code-deploy-service-role" {
  assume_role_policy = data.aws_iam_policy_document.code-deploy-assume-role.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"]
}

resource "aws_iam_role" "demo-app-role" {
  assume_role_policy = data.aws_iam_policy_document.ec2-assume-role.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  ]
}

resource "aws_iam_instance_profile" "demo-app-instance-profile" {
  role = aws_iam_role.demo-app-role.id
}

resource "aws_launch_template" "demo-app-launch-template" {
  name = "demo-app-launch-template"
  instance_type = "t3.micro"
  image_id = data.aws_ami.amazon-linux-2.id
  vpc_security_group_ids = [aws_security_group.demo-instance-security-group.id]
  user_data = base64encode(file("${path.module}/init.sh"))
  iam_instance_profile {
    arn = aws_iam_instance_profile.demo-app-instance-profile.arn
  }
}

resource "aws_autoscaling_group" "demo-app-group" {
  max_size = 2
  min_size = 1
  health_check_type = "ELB"
  termination_policies = [
    "OldestInstance",
    "OldestLaunchTemplate"
  ]
  launch_template {
    id = aws_launch_template.demo-app-launch-template.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.demo-app-target-group.arn]
  vpc_zone_identifier = [local.first-subnet, local.second-subnet]
  instance_refresh {
    strategy = "Rolling"
  }
}

resource "aws_codedeploy_app" "demo-app" {
  compute_platform = "Server"
  name = "demo-app"
}

resource "aws_codedeploy_deployment_config" "all-at-once" {
  deployment_config_name = "app-at-once"
  minimum_healthy_hosts {
    type = "HOST_COUNT"
    value = 0
  }
}

resource "aws_codedeploy_deployment_group" "demo-app-deployment-group" {
  app_name = aws_codedeploy_app.demo-app.name
  deployment_group_name = "demo-app-deployment-group"
  service_role_arn = aws_iam_role.code-deploy-service-role.arn
  autoscaling_groups = [aws_autoscaling_group.demo-app-group.id]
}