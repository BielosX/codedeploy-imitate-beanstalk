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
  validation {
    condition = contains(["ALL_AT_ONCE", "ROLLING", "BLUE_GREEN"], var.deployment-type)
    error_message = "The deployment-type should be one of: ALL_AT_ONCE, ROLLING, BLUE_GREEN."
  }
}

variable "instances-update-policy" {
  type = string
  default = "ONE_AT_A_TIME"
  validation {
    condition = contains(["ALL_AT_ONCE", "ROLLING", "ONE_AT_A_TIME"], var.instances-update-policy)
    error_message = "The instances-update-policy should be one of: ALL_AT_ONCE, ROLLING, ONE_AT_A_TIME."
  }
}

variable "minimum-healthy-hosts" {
  type = number
  default = 1
}

variable "instance-refresh-healthy-percentage" {
  type = string
  default = 90
}

variable "rollback-on-failure" {
  type = bool
  default = true
}

variable "role-id" {
  type = string
}

variable "max-instances" {
  type = number
  default = 4
}

variable "min-instances" {
  type = number
  default = 2
}

variable "load-balancer" {
  type = string
  default = "classic"
  validation {
    condition = contains(["classic", "application"], var.load-balancer)
    error_message = "The load-balancer should be one of: classic, application."
  }
}

variable "internal-lb" {
  type = bool
  default = false
}

variable "allow-ssh" {
  type = bool
  default = false
}