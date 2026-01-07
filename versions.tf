# Konvu On-Prem Controller Module - Provider Versions

terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.us-east-1]
    }
    kubernetes = {
      source                = "hashicorp/kubernetes"
      version               = "~> 2.20"
      configuration_aliases = [kubernetes]
    }
    helm = {
      source                = "hashicorp/helm"
      version               = "~> 2.10"
      configuration_aliases = [helm]
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
