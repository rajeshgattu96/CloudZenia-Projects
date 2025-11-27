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

############################
# 1. Reuse existing Hosted Zone & ACM (from Infra-1)
############################

data "aws_route53_zone" "primary" {
  name         = var.domain
  private_zone = false
}

data "aws_acm_certificate" "main" {
  domain      = var.domain
  statuses    = ["ISSUED"]
  most_recent = true
}

############################
# 2. VPC, Subnets, IGW, NAT
############################

resource "aws_vpc" "ec2_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cloudzenia-ec2-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.ec2_vpc.id

  tags = {
    Name = "cloudzenia-ec2-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.ec2_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "cloudzenia-ec2-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.ec2_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "cloudzenia-ec2-private-${count.index + 1}"
  }
}

# Public route table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.ec2_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "cloudzenia-ec2-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# NAT for private subnets
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "cloudzenia-ec2-nat-eip"
  }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "cloudzenia-ec2-nat-gw"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.ec2_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "cloudzenia-ec2-private-rt"
  }
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

############################
# 3. Security Groups
############################

# ALB SG: allow HTTP/HTTPS from internet
resource "aws_security_group" "alb_sg" {
  name   = "ec2-alb-sg"
  vpc_id = aws_vpc.ec2_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  tags = {
    Name = "ec2-alb-sg"
  }
}

# EC2 SG: only allow traffic from ALB on port 80
resource "aws_security_group" "ec2_sg" {
  name   = "ec2-nginx-sg"
  vpc_id = aws_vpc.ec2_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-nginx-sg"
  }
}

############################
# 4. AMI lookup (Amazon Linux 2023)
############################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

############################
# 5. EC2 Instances in PRIVATE subnets
############################

resource "aws_instance" "web1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.key_name

  # DO NOT assign public IP: private subnet + NAT
  associate_public_ip_address = false

    user_data = <<-EOF
    #!/bin/bash
    set -xe

    yum update -y

    # Install Docker
    yum install -y docker
    systemctl enable docker
    systemctl start docker

    # Run Docker container on 8080 with "Namaste from Container"
    docker run -d --name namaste --restart unless-stopped -p 8080:8080 \
      hashicorp/http-echo -listen=:8080 -text="Namaste from Container"

    # Install NGINX + Certbot
    yum install -y nginx python3 certbot python3-certbot-nginx
    systemctl enable nginx

    # Basic HTTP-only NGINX config so certbot can validate on port 80
    cat > /etc/nginx/nginx.conf << 'NGINXCONF'
    user nginx;
    worker_processes auto;
    error_log /var/log/nginx/error.log notice;
    pid /var/run/nginx.pid;

    events {
        worker_connections 1024;
    }

    http {
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        access_log /var/log/nginx/access.log;
        sendfile on;
        keepalive_timeout 65;

        # Default server - ALB health checks & HTTP access
        server {
            listen 80 default_server;
            server_name _;

            location / {
                add_header Content-Type text/plain;
                return 200 "Hello from Instance 1\n";
            }
        }

        # Docker proxy vhost
        server {
            listen 80;
            server_name ec2-docker1.${var.domain};

            location / {
                proxy_pass http://127.0.0.1:8080;
            }
        }

        # Instance vhost
        server {
            listen 80;
            server_name ec2-instance1.${var.domain};

            location / {
                add_header Content-Type text/plain;
                return 200 "Hello from Instance 1\n";
            }
        }
    }
    NGINXCONF

    systemctl restart nginx

    # --- Let's Encrypt automation ---
    # Wait a bit to give ALB/Route53 time to route traffic correctly
    sleep 60

    # Try certbot up to 10 times in case DNS/ALB is not ready yet
    for i in $(seq 1 10); do
      certbot --nginx \
        --non-interactive \
        --agree-tos \
        --email rajeshgattuaws@gmail.com \
        -d ec2-instance1.${var.domain} \
        -d ec2-docker1.${var.domain} \
        --redirect && break

      echo "Certbot attempt $i failed, retrying in 60s..."
      sleep 60
    done

    # Enable certbot auto-renew (systemd timer usually enabled automatically)
    systemctl restart nginx || true
  EOF


  tags = {
    Name = "cloudzenia-ec2-1"
  }
}

resource "aws_instance" "web2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[1].id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.key_name

  associate_public_ip_address = false

    user_data = <<-EOF
    #!/bin/bash
    set -xe

    yum update -y

    # Install Docker
    yum install -y docker
    systemctl enable docker
    systemctl start docker

    # Run Docker container on 8080 with "Namaste from Container"
    docker run -d --name namaste --restart unless-stopped -p 8080:8080 \
      hashicorp/http-echo -listen=:8080 -text="Namaste from Container"

    # Install NGINX + Certbot
    yum install -y nginx python3 certbot python3-certbot-nginx
    systemctl enable nginx

    # Basic HTTP-only NGINX config so certbot can validate on port 80
    cat > /etc/nginx/nginx.conf << 'NGINXCONF'
    user nginx;
    worker_processes auto;
    error_log /var/log/nginx/error.log notice;
    pid /var/run/nginx.pid;

    events {
        worker_connections 1024;
    }

    http {
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        access_log /var/log/nginx/access.log;
        sendfile on;
        keepalive_timeout 65;

        # Default server - ALB health checks & HTTP access
        server {
            listen 80 default_server;
            server_name _;

            location / {
                add_header Content-Type text/plain;
                return 200 "Hello from Instance 2\n";
            }
        }

        # Docker proxy vhost
        server {
            listen 80;
            server_name ec2-docker2.${var.domain};

            location / {
                proxy_pass http://127.0.0.1:8080;
            }
        }

        # Instance vhost
        server {
            listen 80;
            server_name ec2-instance2.${var.domain};

            location / {
                add_header Content-Type text/plain;
                return 200 "Hello from Instance 2\n";
            }
        }
    }
    NGINXCONF

    systemctl restart nginx

    # --- Let's Encrypt automation ---
    # Wait a bit to give ALB/Route53 time to route traffic correctly
    sleep 60

    # Try certbot up to 10 times in case DNS/ALB is not ready yet
    for i in $(seq 1 10); do
      certbot --nginx \
        --non-interactive \
        --agree-tos \
        --email rajeshgattuaws@gmail.com \
        -d ec2-instance2.${var.domain} \
        -d ec2-docker2.${var.domain} \
        --redirect && break

      echo "Certbot attempt $i failed, retrying in 60s..."
      sleep 60
    done

    # Enable certbot auto-renew (systemd timer usually enabled automatically)
    systemctl restart nginx || true
  EOF


  tags = {
    Name = "cloudzenia-ec2-2"
  }
}

############################
# 6. ALB + Target Groups
############################

resource "aws_lb" "ec2_alb" {
  name               = "cloudzenia-ec2-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb_sg.id]

  tags = {
    Name = "cloudzenia-ec2-alb"
  }
}

# TG for "instance" traffic
resource "aws_lb_target_group" "instance_tg" {
  name        = "ec2-instance-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ec2_vpc.id
  target_type = "instance"

  health_check {
    path     = "/"
    matcher  = "200-399"
    interval = 30
    timeout  = 5
  }

  tags = {
    Name = "ec2-instance-tg"
  }
}

# TG for "docker" traffic
resource "aws_lb_target_group" "docker_tg" {
  name        = "ec2-docker-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ec2_vpc.id
  target_type = "instance"

  health_check {
    path     = "/"
    matcher  = "200-399"
    interval = 30
    timeout  = 5
  }

  tags = {
    Name = "ec2-docker-tg"
  }
}

# Attach both instances to both target groups
resource "aws_lb_target_group_attachment" "instance_tg_web1" {
  target_group_arn = aws_lb_target_group.instance_tg.arn
  target_id        = aws_instance.web1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "instance_tg_web2" {
  target_group_arn = aws_lb_target_group.instance_tg.arn
  target_id        = aws_instance.web2.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "docker_tg_web1" {
  target_group_arn = aws_lb_target_group.docker_tg.arn
  target_id        = aws_instance.web1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "docker_tg_web2" {
  target_group_arn = aws_lb_target_group.docker_tg.arn
  target_id        = aws_instance.web2.id
  port             = 80
}

############################
# 7. ALB Listeners: HTTP→HTTPS, host-based routing
############################

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.ec2_alb.arn
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
  load_balancer_arn = aws_lb.ec2_alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = data.aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.instance_tg.arn
  }
}

# ec2-alb-instance.<domain> + ec2-instance1/2.<domain> → instance_tg
resource "aws_lb_listener_rule" "alb_instance_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.instance_tg.arn
  }

  condition {
    host_header {
      values = [
        "ec2-alb-instance.${var.domain}",
        "ec2-instance1.${var.domain}",
        "ec2-instance2.${var.domain}",
      ]
    }
  }
}

# ec2-alb-docker.<domain> + ec2-docker1/2.<domain> → docker_tg
resource "aws_lb_listener_rule" "alb_docker_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.docker_tg.arn
  }

  condition {
    host_header {
      values = [
        "ec2-alb-docker.${var.domain}",
        "ec2-docker1.${var.domain}",
        "ec2-docker2.${var.domain}",
      ]
    }
  }
}

############################
# 8. Route 53 records (all via ALB)
############################

# Instance URLs
resource "aws_route53_record" "ec2_instance1" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "ec2-instance1.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ec2_alb.dns_name
    zone_id                = aws_lb.ec2_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "ec2_instance2" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "ec2-instance2.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ec2_alb.dns_name
    zone_id                = aws_lb.ec2_alb.zone_id
    evaluate_target_health = false
  }
}

# Docker URLs
resource "aws_route53_record" "ec2_docker1" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "ec2-docker1.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ec2_alb.dns_name
    zone_id                = aws_lb.ec2_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "ec2_docker2" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "ec2-docker2.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ec2_alb.dns_name
    zone_id                = aws_lb.ec2_alb.zone_id
    evaluate_target_health = false
  }
}

# ALB-specific domains
resource "aws_route53_record" "ec2_alb_instance" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "ec2-alb-instance.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ec2_alb.dns_name
    zone_id                = aws_lb.ec2_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "ec2_alb_docker" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "ec2-alb-docker.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ec2_alb.dns_name
    zone_id                = aws_lb.ec2_alb.zone_id
    evaluate_target_health = false
  }
}
