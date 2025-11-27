terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

########################
# Providers
########################

# Default: your main region (for S3 + Route53)
provider "aws" {
  region = var.region
}

# us-east-1 provider (for CloudFront + ACM)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

########################
# Basic data
########################

# Full site domain: static-s3.lakshikabatteryworks.store
locals {
  site_domain = "${var.subdomain}.${var.domain}"
}

# Existing Route53 hosted zone (you already created for the domain)
data "aws_route53_zone" "primary" {
  name         = var.domain
  private_zone = false
}

########################
# S3 Bucket (Private)
########################

resource "aws_s3_bucket" "static_site" {
  bucket = local.site_domain

  tags = {
    Name = "static-site-bucket"
  }
}

# Block all public ACLs – access only via CloudFront
resource "aws_s3_bucket_public_access_block" "static_site_block" {
  bucket = aws_s3_bucket.static_site.id

  block_public_acls       = true
  block_public_policy     = false 
  ignore_public_acls      = true
  restrict_public_buckets = false
}

# Ownership controls
resource "aws_s3_bucket_ownership_controls" "static_site_ownership" {
  bucket = aws_s3_bucket.static_site.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

########################
# ACM Certificate in us-east-1 (for CloudFront)
########################

resource "aws_acm_certificate" "static_cert" {
  provider          = aws.us_east_1
  domain_name       = local.site_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "static-site-cert"
  }
}

# DNS validation records
resource "aws_route53_record" "static_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.static_cert.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.primary.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "static_cert_validation" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.static_cert.arn
  validation_record_fqdns = [for r in aws_route53_record.static_cert_validation : r.fqdn]
}

########################
# CloudFront Origin Access Control (OAC)
########################

resource "aws_cloudfront_origin_access_control" "static_oac" {
  provider = aws.us_east_1

  name                              = "static-site-oac"
  description                       = "OAC for S3 static site"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

########################
# CloudFront Distribution
########################

resource "aws_cloudfront_distribution" "static_cdn" {
  provider = aws.us_east_1

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Static site CDN for ${local.site_domain}"
  default_root_object = "index.html"

  aliases = [local.site_domain]

  origin {
    domain_name = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id   = "s3-${aws_s3_bucket.static_site.id}"

    origin_access_control_id = aws_cloudfront_origin_access_control.static_oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-${aws_s3_bucket.static_site.id}"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  price_class = "PriceClass_100" 

  restrictions {
    geo_restriction {
      restriction_type = length(var.blocked_countries) > 0 ? "blacklist" : "none"
      locations        = var.blocked_countries
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.static_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [
    aws_acm_certificate_validation.static_cert_validation
  ]

  tags = {
    Name = "static-site-distribution"
  }
}

########################
# Bucket Policy – allow CloudFront OAC to read objects
########################

data "aws_iam_policy_document" "static_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.static_site.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.static_cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static_site_policy" {
  bucket = aws_s3_bucket.static_site.id
  policy = data.aws_iam_policy_document.static_bucket_policy.json
}
resource "aws_route53_record" "static_site_alias" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = local.site_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.static_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.static_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}
