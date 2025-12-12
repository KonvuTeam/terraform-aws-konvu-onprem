  variable "aws_region" {
    description = "AWS region"
    type        = string
    default     = "us-east-2"
  }

  variable "cluster_name" {
    description = "EKS cluster name"
    type        = string
    default     = "konvu-onprem"
  }

  variable "backend_url" {
    description = "Konvu backend URL"
    type        = string
    default     = "https://sensors.konvu.com"
  }

  variable "cluster_admin_role_arns" {
    description = "IAM role ARNs for cluster admin access"
    type        = list(string)
    default     = []
  }

  variable "deploy_kubernetes_resources" {
    description = "Deploy Kubernetes resources (Stage 2)"
    type        = bool
    default     = false
  }

  variable "vpc_cidr" {
    description = "VPC CIDR block"
    type        = string
    default     = "10.0.0.0/16"
  }

  variable "availability_zones" {
    description = "Availability zones (empty = auto-select first 2)"
    type        = list(string)
    default     = []
  }

  variable "company_token_secret_name" {
    description = "AWS Secrets Manager secret name for company token"
    type        = string
    default     = "konvu-company-token"
  }

  variable "github_token_secret_name" {
    description = "AWS Secrets Manager secret name for GitHub token"
    type        = string
    default     = "konvu-github-token"
  }

  variable "openai_key_secret_name" {
    description = "AWS Secrets Manager secret name for OpenAI key"
    type        = string
    default     = "konvu-openai-key"
  }

  variable "resource_quota_preset" {
    description = "Resource quota preset (small/medium/large)"
    type        = string
    default     = "medium"
  }

  variable "tags" {
    description = "Tags to apply to resources"
    type        = map(string)
    default = {
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
