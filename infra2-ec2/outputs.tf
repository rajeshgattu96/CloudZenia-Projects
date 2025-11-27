output "alb_dns" {
  value = aws_lb.ec2_alb.dns_name
}

output "instance_urls" {
  value = [
    "https://ec2-instance1.${var.domain}",
    "https://ec2-instance2.${var.domain}",
  ]
}

output "docker_urls" {
  value = [
    "https://ec2-docker1.${var.domain}",
    "https://ec2-docker2.${var.domain}",
  ]
}

output "alb_urls" {
  value = [
    "https://ec2-alb-instance.${var.domain}",
    "https://ec2-alb-docker.${var.domain}",
  ]
}
