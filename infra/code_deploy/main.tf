data "aws_ami" "app-image" {
  most_recent = true
  filter {
    name   = "tag:Name"
    values = [var.app-image-name]
  }
  owners = ["self"]
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region = data.aws_region.current.name
}

resource "aws_s3_bucket" "deployment-bucket" {
  bucket = "${var.app-name}-artifacts-${local.region}-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "deployment-bucket-acl" {
  bucket = aws_s3_bucket.deployment-bucket.id
  acl = "private"
}

resource "aws_security_group" "lb-security-group" {
  vpc_id = var.vpc_id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = var.lb-listener-port
    to_port = var.lb-listener-port
    protocol = "tcp"
  }
  egress {
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
    from_port = var.nginx-port
    to_port = var.nginx-port
    protocol = "tcp"
  }
}

resource "aws_security_group" "instance-security-group" {
  vpc_id = var.vpc_id
  ingress {
    security_groups = [aws_security_group.lb-security-group.id]
    from_port = var.nginx-port
    to_port = var.nginx-port
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

resource "aws_lb" "app-lb" {
  name = "${var.app-name}-lb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.lb-security-group.id]
  subnets = var.elb-subnets
}

resource "aws_lb_target_group" "app-target-group" {
  name = "${var.app-name}-target-group"
  protocol = "HTTP"
  port = var.nginx-port
  vpc_id = var.vpc_id
  deregistration_delay = 20
  health_check {
    enabled = true
    matcher = "200"
    path = var.app-health-path
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 5
    interval = 10
  }
}

resource "aws_alb_listener" "default-listener" {
  load_balancer_arn = aws_lb.app-lb.arn
  protocol = "HTTP"
  port = 80
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.app-target-group.arn
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
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  ]
}

resource "aws_iam_instance_profile" "app-instance-profile" {
  role = var.role-id
}

resource "aws_launch_template" "app-launch-template" {
  name = "${var.app-name}-launch-template"
  instance_type = "t3.micro"
  image_id = data.aws_ami.app-image.id
  vpc_security_group_ids = [aws_security_group.instance-security-group.id]
  user_data = base64encode(join("\n", [for key, value in var.environment_variables : "${key}=${value}"]))
  iam_instance_profile {
    arn = aws_iam_instance_profile.app-instance-profile.arn
  }
}

resource "aws_autoscaling_group" "app-group" {
  max_size = var.max-instances
  min_size = var.min-instances
  health_check_type = "ELB"
  termination_policies = [
    "OldestInstance",
    "OldestLaunchTemplate"
  ]
  launch_template {
    id = aws_launch_template.app-launch-template.id
    version = aws_launch_template.app-launch-template.latest_version
  }
  vpc_zone_identifier = var.app-subnets
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
    }
  }
}

resource "aws_codedeploy_app" "app" {
  compute_platform = "Server"
  name = var.app-name
}

resource "aws_codedeploy_deployment_config" "app-deployment-config" {
  deployment_config_name = "${var.app-name}-deployment-config"
  minimum_healthy_hosts {
    type = "HOST_COUNT"
    value = var.deployment-type == "ALL_AT_ONCE" ? 0 : var.minimum-healthy-hosts
  }
}

resource "aws_codedeploy_deployment_group" "app-deployment-group" {
  app_name = aws_codedeploy_app.app.name
  deployment_group_name = "${var.app-name}-deployment-group"
  service_role_arn = aws_iam_role.code-deploy-service-role.arn
  autoscaling_groups = [aws_autoscaling_group.app-group.id]
  deployment_config_name = aws_codedeploy_deployment_config.app-deployment-config.id
  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.app-target-group.name
    }
  }
  auto_rollback_configuration {
    enabled = var.rollback-on-failure
    events = ["DEPLOYMENT_FAILURE"]
  }
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type = "IN_PLACE"
  }
}

