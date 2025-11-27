variable "name" {
  default = "cloudzenia"
}

variable "region" {
  default = "ap-south-1"
}

variable "private_subnets" {
  default = []
}

variable "service_sg_id" {
  default = ""
}

variable "wordpress_image" {
  default = "wordpress:latest"
}

variable "micro_image" {
  default = ""
}

variable "rds_endpoint" {
  default = ""
}

variable "rds_db_name" {
  default = "wordpressdb"
}

variable "rds_db_user" {
  default = "wp_user"
}

variable "db_secret_arn" {
  default = ""
}

variable "tg_arn_wordpress" {
  default = ""
}

variable "tg_arn_microservice" {
  default = ""
}

variable "log_group" {
  default = "/cloudzenia/microservice"
}
