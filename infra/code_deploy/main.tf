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
  dynamic "ingress" {
    for_each = var.allow-ssh ? ["VALUE"] : []
    content {
      cidr_blocks = ["0.0.0.0/0"]
      from_port = 22
      to_port = 22
      protocol = "tcp"
    }
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 443
    to_port = 443
    protocol = "tcp"
  }
}

resource "aws_elb" "classic-lb" {
  count = var.load-balancer == "classic" ? 1 : 0
  name = "${var.app-name}-classic-lb"
  internal = var.internal-lb
  security_groups = [aws_security_group.lb-security-group.id]
  subnets = var.elb-subnets
  listener {
    instance_port = var.nginx-port
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }
  health_check {
    healthy_threshold = 2
    interval = 10
    target = "HTTP:${var.nginx-port}${var.app-health-path}"
    timeout = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb" "app-lb" {
  count = var.load-balancer == "application" ? 1 : 0
  name = "${var.app-name}-lb"
  internal = var.internal-lb
  load_balancer_type = "application"
  security_groups = [aws_security_group.lb-security-group.id]
  subnets = var.elb-subnets
}

resource "aws_lb_target_group" "app-target-group" {
  count = var.load-balancer == "application" ? 1 : 0
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
  count = var.load-balancer == "application" ? 1 : 0
  load_balancer_arn = aws_lb.app-lb[0].arn
  protocol = "HTTP"
  port = 80
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.app-target-group[0].arn
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
  metadata_options {
    http_endpoint = "enabled"
    http_tokens = "required"
    http_protocol_ipv6 = "disabled"
    http_put_response_hop_limit = 1
    instance_metadata_tags = "enabled"
  }
}

locals {
  update-policy-to-health-percentage = {
    "ALL_AT_ONCE": 0,
    "ROLLING": var.instance-refresh-healthy-percentage,
    "ONE_AT_A_TIME": 99
  }
}

resource "aws_autoscaling_group" "app-group" {
  count = var.deployment-type == "BLUE_GREEN" ? 2 : 1
  name = "${var.app-name}-asg-${count.index}"
  max_size = var.max-instances
  min_size = var.min-instances
  health_check_type = "ELB"
  health_check_grace_period = 60
  enabled_metrics = ["GroupInServiceInstances", "GroupDesiredCapacity"]
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
      min_healthy_percentage = lookup(local.update-policy-to-health-percentage, var.instances-update-policy, 90)
    }
  }
  tag {
    key = "Name"
    propagate_at_launch = true
    value = var.app-name
  }
}

resource "aws_autoscaling_policy" "app-scale-up-policy" {
  count = var.deployment-type == "BLUE_GREEN" ? 2 : 1
  autoscaling_group_name = aws_autoscaling_group.app-group[count.index].name
  name = "${var.app-name}-scaling-policy-${count.index}"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = 1
  cooldown = 60
}

resource "aws_cloudwatch_metric_alarm" "app-network-outbound-high" {
  count = var.deployment-type == "BLUE_GREEN" ? 2 : 1
  alarm_name = "${var.app-name}-network-outbound-high-${count.index}"
  comparison_operator = "GreaterThanThreshold"
  statistic = "Average"
  evaluation_periods = 5
  period = 60
  actions_enabled = true
  namespace = "AWS/EC2"
  metric_name = "NetworkOut"
  threshold = 6 * 1024 * 1024
  alarm_actions = [aws_autoscaling_policy.app-scale-up-policy[count.index].arn]
}

resource "aws_autoscaling_policy" "app-scale-down-policy" {
  count = var.deployment-type == "BLUE_GREEN" ? 2 : 1
  autoscaling_group_name = aws_autoscaling_group.app-group[count.index].name
  name = "${var.app-name}-scaling-policy-${count.index}"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = -1
  cooldown = 60
}

resource "aws_cloudwatch_metric_alarm" "app-network-outbound-low" {
  count = var.deployment-type == "BLUE_GREEN" ? 2 : 1
  alarm_name = "${var.app-name}-network-outbound-low-${count.index}"
  comparison_operator = "LessThanThreshold"
  statistic = "Average"
  evaluation_periods = 5
  period = 60
  actions_enabled = true
  namespace = "AWS/EC2"
  metric_name = "NetworkOut"
  threshold = 2 * 1024 * 1024
  alarm_actions = [aws_autoscaling_policy.app-scale-down-policy[count.index].arn]
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
  autoscaling_groups = [aws_autoscaling_group.app-group[0].id]
  deployment_config_name = aws_codedeploy_deployment_config.app-deployment-config.id
  load_balancer_info {
    dynamic "target_group_info" {
      for_each = var.load-balancer == "application" ? ["VALUE"] : []
      content {
        name = aws_lb_target_group.app-target-group[0].name
      }
    }
    dynamic "elb_info" {
      for_each = var.load-balancer == "classic" ? ["VALUE"] : []
      content {
        name = aws_elb.classic-lb[0].name
      }
    }
  }
  auto_rollback_configuration {
    enabled = var.rollback-on-failure
    events = ["DEPLOYMENT_FAILURE"]
  }
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type = var.deployment-type != "BLUE_GREEN" ? "IN_PLACE" : "BLUE_GREEN"
  }
  dynamic "blue_green_deployment_config" {
    for_each = var.deployment-type == "BLUE_GREEN" ? ["VALUE"] : []
    content {
      green_fleet_provisioning_option {
        action = "DISCOVER_EXISTING"
      }
      deployment_ready_option {
        action_on_timeout = "CONTINUE_DEPLOYMENT"
      }
      terminate_blue_instances_on_deployment_success {
        action = "KEEP_ALIVE" // TERMINATING removes ASG, not instances
      }
    }
  }
  lifecycle {
    ignore_changes = [autoscaling_groups]
    replace_triggered_by = [aws_codedeploy_deployment_config.app-deployment-config.id]
  }
}

