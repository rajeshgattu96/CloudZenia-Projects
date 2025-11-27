output "s3_bucket_name" {
  value = aws_s3_bucket.static_site.bucket
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.static_cdn.domain_name
}

output "static_website_url" {
  value = "https://${local.site_domain}"
}
