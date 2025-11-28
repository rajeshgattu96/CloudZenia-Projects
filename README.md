**Running Endpoint:**

**S3 static website**

https://static-s3.lakshikabatteryworks.store/

**ECS**

https://wordpress.lakshikabatteryworks.store

https://microservice.lakshikabatteryworks.store

**EC2**

http://ec2-docker1.lakshikabatteryworks.store → Namaste from Container

http://ec2-docker2.lakshikabatteryworks.store → Namaste from Container

http://ec2-instance1.lakshikabatteryworks.store → Hello from Instance 1

http://ec2-instance2.lakshikabatteryworks.store → Hello from Instance 2

**CloudZenia Hands-On Assignment — Solution by Rajesh**

This project delivers three independent AWS infrastructures using Terraform, aligned with the assignment requirements.
**Architecture Summary:**
This setup hosts:
**Infra-1 — ECS + ALB + RDS**
1.WordPress container

2.Custom Microservice (Node.js) — pushed through GitHub Actions CI/CD

3.MySQL RDS in private subnet

4.Database credentials stored in SecretsManager

5.ACM TLS certificate + HTTPS-only ALB

6.Domain mapping

**Infra-2 — EC2 + Docker + NGINX (Private Instances)**

Two EC2 instances running in private subnets

No public IP exposure

Traffic routed through ALB only

Each instance hosts:

NGINX (Hello from Instance)

Docker container (Namaste from Container)

Host-based routing via ALB


**Infra-3 — S3 Static Website + CloudFront CDN**

S3 bucket: static-s3.<domain>

Website deployed through GitHub Actions pipeline

CloudFront distribution enabled for:

Low latency caching

Global content delivery

Geo-restriction (configured to block selected countries)

Domain mapped to CloudFront via Route53

HTTPS enabled using ACM in us-east-1

Pipeline:

On push to main, GitHub deploys static assets to S3

CloudFront invalidation issued automatically to refresh CDN cache

**CI/CD Details**
**Microservice Pipeline (ECS Deployment**)

Build Docker image

Push to Amazon ECR

Update ECS service → triggers rolling deployment

**Static Website Pipeline (S3 CDN)**

Upload static files to S3 bucket

CloudFront invalidation to refresh cached content
