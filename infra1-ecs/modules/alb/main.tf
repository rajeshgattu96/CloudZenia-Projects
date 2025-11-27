resource "aws_lb" "app_lb" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnets
  security_groups    = [var.alb_sg_id]

  tags = {
    Name = "${var.name}-alb"
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name        = "${var.name}-wp-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path     = "/"
    matcher  = "200-399"
    interval = 30
    timeout  = 5
  }
}

resource "aws_lb_target_group" "microservice_tg" {
  name        = "${var.name}-micro-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path     = "/"
    matcher  = "200-399"
    interval = 30
    timeout  = 5
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_listener_rule" "wordpress_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }

  condition {
    host_header {
      values = ["wordpress.${var.domain}"]
    }
  }
}

resource "aws_lb_listener_rule" "microservice_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.microservice_tg.arn
  }

  condition {
    host_header {
      values = ["microservice.${var.domain}"]
    }
  }
}
