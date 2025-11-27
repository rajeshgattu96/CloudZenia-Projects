variable "region" {
  description = "Primary AWS region (for S3/Route53)"
  default     = "ap-south-1"
}

variable "domain" {
  description = "Root domain"
  default     = "lakshikabatteryworks.store"
}

variable "subdomain" {
  description = "Subdomain for static site"
  default     = "static-s3"
}

variable "blocked_countries" {
  description = "List of country codes to block in CloudFront (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = ["CN", "RU"] # change as you like
}
