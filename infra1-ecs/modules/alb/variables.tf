variable "name" {
  default = "cloudzenia"
}

variable "domain" {
  default = "lakshikabatteryworks.store"
}

variable "public_subnets" {
  default = []
}

variable "vpc_id" {
  default = ""
}

variable "alb_sg_id" {
  default = ""
}

variable "certificate_arn" {
  default = ""
}
