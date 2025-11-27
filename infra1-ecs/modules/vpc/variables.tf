variable "name" {
  default = "cloudzenia-ecs"
}

variable "vpc_cidr" {
  default = "10.10.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.10.1.0/24", "10.10.2.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.10.11.0/24", "10.10.12.0/24"]
}

variable "azs" {
  default = ["ap-south-1a", "ap-south-1b"]
}
