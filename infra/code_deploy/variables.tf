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
