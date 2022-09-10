output "lb_dns_name" {
  value = var.load-balancer == "application" ? aws_lb.app-lb[0].dns_name : aws_elb.classic-lb[0].dns_name
}