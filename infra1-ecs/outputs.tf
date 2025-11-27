output "alb_dns" {
  value = module.alb.alb_dns
}

output "wordpress_url" {
  value = "https://wordpress.${var.domain}"
}

output "microservice_url" {
  value = "https://microservice.${var.domain}"
}

output "rds_endpoint" {
  value = module.rds.endpoint
}
