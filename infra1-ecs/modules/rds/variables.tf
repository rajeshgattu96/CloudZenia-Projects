variable "name" {
  default = "cloudzenia-db"
}

variable "identifier" {
  default = "cloudzenia-db"
}

variable "engine" {
  default = "mysql"
}

variable "engine_version" {
  default = "8.0"
}

variable "instance_class" {
  default = "db.t3.micro"
}

variable "allocated_storage" {
  default = 20
}

variable "username" {
  default = "wp_user"
}

variable "password" {
  default = "ChangeMe123!"
}

variable "database_name" {
  default = "wordpressdb"
}

variable "private_subnets" {
  default = []
}

variable "sg_id" {
  default = ""
}

variable "backup_retention" {
  default = 7
}
