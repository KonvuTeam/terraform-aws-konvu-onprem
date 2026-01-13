# Konvu On-Prem Infrastructure Module - Variables
# This module creates a dedicated VPC and EKS cluster for running Konvu workloads

## Network Configuration
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be /23 or larger (smaller prefix) to allow /24 subnet allocation."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.vpc_cidr))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block (e.g., 10.0.0.0/16)."
  }

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) <= 23
    error_message = "VPC CIDR prefix must be /23 or larger (e.g., /16, /20, /23) to support /24 subnet allocation. Prefix /${tonumber(split("/", var.vpc_cidr)[1])} is too small."
  }
}

variable "availability_zones" {
  description = "List of availability zones. If not specified, will use first 2 AZs in the region. Maximum 6 AZs to prevent subnet CIDR overlap."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.availability_zones) <= 6
    error_message = "Maximum 6 availability zones supported. Current subnet allocation uses offset of 10 for private subnets, which would cause overlap with more than 6 AZs."
  }
}

## EKS Cluster Configuration
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "cluster_admin_role_arns" {
  description = "List of IAM role ARNs to grant cluster administrator access. If empty, no additional admin access is granted."
  type        = list(string)
  default     = []
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the EKS public API endpoint. Defaults to open (0.0.0.0/0) for initial setup and testing. IMPORTANT: Restrict this in production to specific IP ranges (e.g., your office/VPN CIDR) to reduce attack surface."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "At least one CIDR block must be specified for cluster endpoint access."
  }
}

variable "deploy_kubernetes_resources" {
  description = "Deploy Kubernetes Helm releases (Stage 2a). Set to false for Stage 1 (AWS infrastructure only), true for Stage 2."
  type        = bool
  default     = false
}

variable "deploy_kubernetes_manifests" {
  description = "Deploy Kubernetes manifests that depend on CRDs (Stage 3). Requires deploy_kubernetes_resources=true."
  type        = bool
  default     = false
}

## Managed Node Group Configuration (for bootstrap)
variable "enable_managed_node_group" {
  description = "Enable managed node group for system pods (CoreDNS, Karpenter). Highly recommended to solve bootstrap chicken-egg problem."
  type        = bool
  default     = true
}

variable "system_node_instance_type" {
  description = "Instance type for system node group (runs CoreDNS, Karpenter, External Secrets)"
  type        = string
  default     = "t3.small"
}

variable "system_node_count" {
  description = "Number of nodes in system node group (recommend 2 for HA across availability zones)"
  type        = number
  default     = 2

  validation {
    condition     = var.system_node_count >= 1 && var.system_node_count <= 5
    error_message = "System node count must be between 1 and 5."
  }
}

## AWS Secrets Manager Configuration
variable "company_token_secret_name" {
  description = "Name of AWS Secrets Manager secret containing the Konvu company token"
  type        = string
}

variable "github_app_credentials_secret_name" {
  description = "Name of AWS Secrets Manager secret containing GitHub App credentials (JSON with appId, installationId, privateKey) for broker repository syncing"
  type        = string
}

variable "openai_key_secret_name" {
  description = "Name of AWS Secrets Manager secret containing the OpenAI API key"
  type        = string
}

## Broker Configuration
variable "broker_install_crds" {
  description = "Install External Secrets CRDs in broker namespace. Set to false when controller and broker are in the same cluster (CRDs already installed by controller). Set to true for multi-cluster deployments where broker is in a separate cluster."
  type        = bool
  default     = false
}

## Additional Configuration
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

## Karpenter Spot Instance Configuration
variable "enable_spot_service_linked_role" {
  description = "Create the EC2 Spot service-linked role required for Karpenter to provision spot instances. Set to false if the role already exists in your AWS account. Note: This only creates the IAM role - NodePool configuration separately controls whether spot capacity is used."
  type        = bool
  default     = true
}
