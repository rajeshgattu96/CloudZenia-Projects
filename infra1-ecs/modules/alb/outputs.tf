output "alb_dns" {
  value = aws_lb.app_lb.dns_name
}

output "alb_zone_id" {
  value = aws_lb.app_lb.zone_id
}

output "tg_arn_wordpress" {
  value = aws_lb_target_group.wordpress_tg.arn
}

output "tg_arn_microservice" {
  value = aws_lb_target_group.microservice_tg.arn
}
