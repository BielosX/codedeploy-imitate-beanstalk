variable "app-name" {
  type = string
}
variable "app-image-name" {
  type = string
}

variable "nginx-port" {
  type = number
  default = 8080
}

variable "lb-listener-port" {
  type = number
  default = 80
}

variable "app-health-path" {
  type = string
  default = "/health"
}

variable "vpc_id" {
  type = string
}

variable "app-subnets" {
  type = list(string)
}

variable "elb-subnets" {
  type = list(string)
}

variable "environment_variables" {
  type = map(string)
}

variable "deployment-type" {
  type = string
  default = "ALL_AT_ONCE"
}

variable "minimum_healthy_hosts" {
  type = number
  default = 1
}
