  terraform {
    required_version = "~> 1.9"

    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "~> 5.0"
      }
      kubernetes = {
        source  = "hashicorp/kubernetes"
        version = "~> 2.20"
      }
      helm = {
        source  = "hashicorp/helm"
        version = "~> 2.10"
      }
    }
  }

  provider "aws" {
    region = var.aws_region
  }

  provider "aws" {
    alias  = "us-east-1"
    region = "us-east-1"
  }

  provider "kubernetes" {
    host                   = try(module.konvu_onprem.cluster_endpoint, "")
    cluster_ca_certificate =
  try(base64decode(module.konvu_onprem.cluster_certificate_authority_data), "")
    token                  = try(data.aws_eks_cluster_auth.main.token, "")
  }

  provider "helm" {
    kubernetes {
      host                   = try(module.konvu_onprem.cluster_endpoint, "")
      cluster_ca_certificate =
  try(base64decode(module.konvu_onprem.cluster_certificate_authority_data), "")
      token                  = try(data.aws_eks_cluster_auth.main.token, "")
    }
  }

  data "aws_eks_cluster_auth" "main" {
    name = var.cluster_name
  }

  module "konvu_onprem" {
    source = "git::https://github.com/KonvuTeam/terraform-aws-konvu-onprem.git?ref=v1.0.0"

    providers = {
      aws           = aws
      aws.us-east-1 = aws.us-east-1
      kubernetes    = kubernetes
      helm          = helm
    }

    aws_region   = var.aws_region
    cluster_name = var.cluster_name
    backend_url  = var.backend_url

    cluster_admin_role_arns = var.cluster_admin_role_arns

    deploy_kubernetes_resources = var.deploy_kubernetes_resources

    vpc_cidr           = var.vpc_cidr
    availability_zones = var.availability_zones

    company_token_secret_name       = var.company_token_secret_name
    github_app_credentials_secret_name = var.github_app_credentials_secret_name
    openai_key_secret_name          = var.openai_key_secret_name

    resource_quota_preset = var.resource_quota_preset
    tags                  = var.tags
  }

  output "cluster_endpoint" {
    description = "EKS cluster endpoint"
    value       = module.konvu_onprem.cluster_endpoint
  }

  output "cluster_name" {
    description = "EKS cluster name"
    value       = module.konvu_onprem.cluster_name
  }

  output "vpc_id" {
    description = "VPC ID"
    value       = module.konvu_onprem.vpc_id
  }
