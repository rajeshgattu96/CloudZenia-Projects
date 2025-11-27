terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = var.region
}

########################
# 1. Route 53 Hosted Zone
########################

resource "aws_route53_zone" "primary_zone" {
  name = var.domain
}

########################
# 2. ACM Certificate (HTTPS)
########################

resource "aws_acm_certificate" "main_cert" {
  domain_name               = var.domain
  validation_method         = "DNS"
  subject_alternative_names = [
    "wordpress.${var.domain}",
    "microservice.${var.domain}",
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation_records" {
  for_each = {
    for dvo in aws_acm_certificate.main_cert.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.primary_zone.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.main_cert.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation_records : r.fqdn]
}

########################
# 3. VPC (infra-1 isolated)
########################

module "vpc" {
  source               = "./modules/vpc"
  name                 = "cloudzenia-ecs"
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  azs                  = var.azs
}

########################
# 4. Security Groups
########################

# ALB SG: allow HTTPS from internet
resource "aws_security_group" "alb_sg" {
  name   = "ecs-alb-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS tasks SG: only ALB on 80/8080
resource "aws_security_group" "ecs_tasks_sg" {
  name   = "ecs-tasks-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS SG: only ECS tasks SG on 3306
resource "aws_security_group" "rds_sg" {
  name   = "ecs-rds-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

########################
# 5. RDS (MySQL in private subnets)
########################

module "rds" {
  source          = "./modules/rds"
  name            = "cloudzenia-db"
  identifier      = "cloudzenia-db"
  engine          = "mysql"
  engine_version  = "8.0"
  instance_class  = var.rds_instance_class
  allocated_storage = 20
  username        = var.db_username
  password        = var.db_password
  database_name   = var.db_name
  private_subnets = module.vpc.private_subnets
  sg_id           = aws_security_group.rds_sg.id
}

########################
# 6. Secrets Manager (DB creds)
########################

module "db_secret" {
  source   = "./modules/sm"
  name     = "cloudzenia-db-credentials"
  username = var.db_username
  password = var.db_password
  host     = module.rds.endpoint
  port     = 3306
  dbname   = var.db_name
}

########################
# 7. ECR (for microservice image)
########################

module "micro_ecr" {
  source = "./modules/ecr"
  name   = "cloudzenia-microservice"
}

########################
# 8. ALB (HTTPS, host-based routing)
########################

module "alb" {
  source          = "./modules/alb"
  name            = "cloudzenia"
  domain          = var.domain
  public_subnets  = module.vpc.public_subnets
  vpc_id          = module.vpc.vpc_id
  alb_sg_id       = aws_security_group.alb_sg.id
  certificate_arn = aws_acm_certificate_validation.cert_validation.certificate_arn
}

########################
# 9. ECS Cluster + Services
########################

module "ecs" {
  source              = "./modules/ecs"
  name                = "cloudzenia"
  region              = var.region
  private_subnets     = module.vpc.private_subnets
  service_sg_id       = aws_security_group.ecs_tasks_sg.id
  wordpress_image     = "wordpress:latest"
  micro_image         = "${module.micro_ecr.repository_url}:latest"
  rds_endpoint        = module.rds.endpoint
  rds_db_name         = var.db_name
  rds_db_user         = var.db_username
  db_secret_arn       = module.db_secret.secret_arn
  tg_arn_wordpress    = module.alb.tg_arn_wordpress
  tg_arn_microservice = module.alb.tg_arn_microservice
  depends_on = [
    module.alb
  ]
}

########################
# 10. Route 53 records for subdomains
########################

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.primary_zone.zone_id
  name    = "wordpress.${var.domain}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "microservice_record" {
  zone_id = aws_route53_zone.primary_zone.zone_id
  name    = "microservice.${var.domain}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = false
  }
}
