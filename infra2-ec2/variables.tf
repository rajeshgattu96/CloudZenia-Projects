variable "region" {
  default = "ap-south-1"
}

variable "domain" {
  default = "lakshikabatteryworks.store"
}

variable "vpc_cidr" {
  default = "10.30.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.30.1.0/24", "10.30.2.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.30.11.0/24", "10.30.12.0/24"]
}

variable "azs" {
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "instance_type" {
  default = "t3.micro"
}

# optional if you want SSH; can be left empty
variable "key_name" {
  default = ""
}
