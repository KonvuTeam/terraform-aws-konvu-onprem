# Konvu On-Premises Infrastructure - Terraform Module

This Terraform module provisions production-ready AWS infrastructure for running the Konvu On-Premises Controller.

## Overview

This module prepares all necessary AWS infrastructure for the Konvu On-Premises Controller, which enables distributed security analysis of your private repositories without sending code to external services.

**What this module provides:**
- **Dedicated VPC** with public/private subnet architecture
- **Amazon EKS cluster** with Kubernetes 1.31
- **Karpenter autoscaling** for cost-effective compute using Spot instances
- **External Secrets Operator** for secure credential management
- **Kubernetes namespace and IRSA** for the Konvu Controller

**What this module does NOT include:**
- The module does **not** deploy the Konvu Controller itself
- Controller deployment via Helm is a separate step performed after infrastructure is ready
- See the [Konvu documentation](https://docs.konvu.com) for controller installation instructions

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ AWS Account                                                 │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ VPC (10.0.0.0/16)                                   │   │
│  │                                                     │   │
│  │  ┌──────────────┐         ┌──────────────┐        │   │
│  │  │ Public Subnet│         │ Public Subnet│        │   │
│  │  │  (AZ-1)      │         │  (AZ-2)      │        │   │
│  │  │              │         │              │        │   │
│  │  │  NAT Gateway │         │              │        │   │
│  │  └──────────────┘         └──────────────┘        │   │
│  │         │                        │                │   │
│  │  ┌──────────────┐         ┌──────────────┐        │   │
│  │  │Private Subnet│         │Private Subnet│        │   │
│  │  │  (AZ-1)      │         │  (AZ-2)      │        │   │
│  │  │              │         │              │        │   │
│  │  │ ┌──────────┐ │         │ ┌──────────┐ │        │   │
│  │  │ │   EKS    │ │         │ │   EKS    │ │        │   │
│  │  │ │  Nodes   │ │         │ │  Nodes   │ │        │   │
│  │  │ │          │ │         │ │          │ │        │   │
│  │  │ │ Karpenter│ │         │ │ Karpenter│ │        │   │
│  │  │ │(Spot/On-D)│ │        │ │(Spot/On-D)│ │        │   │
│  │  │ └──────────┘ │         │ └──────────┘ │        │   │
│  │  │              │         │              │        │   │
│  │  │ (Ready for controller  │              │        │   │
│  │  │  deployment)           │              │        │   │
│  │  └──────────────┘         └──────────────┘        │   │
│  │                                                     │   │
│  │  VPC Endpoints: S3, ECR API, ECR DKR               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ AWS Secrets Manager                                 │   │
│  │  • Konvu Company Token                              │   │
│  │  • GitHub App Credentials (appId, installation, key)│   │
│  │  • OpenAI API Key                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

Before using this module, ensure you have:

1. **AWS Account**: With sufficient permissions to create VPC, EKS, IAM, and related resources
2. **AWS CLI**: Configured with credentials (`aws configure` or SSO)
3. **Terraform/OpenTofu**: Version 1.9 or later
4. **Git**: For downloading the module from GitHub
5. **Konvu Company Token**: Obtained from Konvu (format: `comp_xxxxxxxxxxxxx`)
   - Used at runtime for controller and broker authentication with Konvu backend
   - Contact support@konvu.com to obtain your company token
6. **GitHub App Credentials** (for broker): App ID, Installation ID, and Private Key
   - Create GitHub App in your GitHub Enterprise instance or GitHub.com
   - Install app on organizations/repositories you want to sync
   - Store credentials in AWS Secrets Manager as JSON
7. **OpenAI API Key** (optional): For AI-powered qualification and criticality analysis

### Required AWS Permissions

Your AWS credentials need permissions for:
- VPC management (create VPC, subnets, route tables, NAT gateway, IGW)
- EKS cluster management
- IAM role and policy management
- Secrets Manager (if not pre-creating secrets)
- EC2 (for Karpenter node provisioning)

## Two-Stage Deployment

**IMPORTANT**: This module requires a two-stage deployment due to AWS EKS architecture constraints.

### Why Two Stages?

The Kubernetes and Helm providers need to connect to the EKS cluster endpoint to deploy resources. However, the cluster doesn't exist during the initial `terraform plan`. This creates a "chicken-and-egg" problem:

- **Stage 1** cannot deploy Kubernetes resources because the cluster doesn't exist yet
- **Stage 2** can deploy Kubernetes resources because the cluster now exists and providers can connect

This is a standard pattern for EKS deployments and is handled automatically by the module using the `deploy_kubernetes_resources` variable.

### What Happens in Each Stage

**Stage 1** (AWS Infrastructure):
- VPC with public/private subnets, NAT gateway, Internet gateway
- EKS cluster control plane
- IAM roles and policies (cluster, nodes, service accounts)
- Security groups with Karpenter discovery tags
- VPC endpoints (S3, ECR)
- OIDC provider for IRSA
- Karpenter infrastructure (IAM, SQS)
- Karpenter Helm chart (CRDs and controller)

**Stage 2** (Kubernetes Resources):
- Karpenter NodePool and EC2NodeClass
- External Secrets Operator
- Kubernetes namespaces: konvu-controller, konvu-broker
- SecretStores (one per namespace)
- ExternalSecrets:
  - Controller: company-token, ai-credentials
  - Broker: company-token, git-credentials (GitHub App)

**After Stage 2**: Your infrastructure is ready for controller and broker deployment via Helm (see Konvu documentation).

## Quick Start

### 1. Create AWS Secrets

Before deploying, create three secrets in AWS Secrets Manager:

```bash
# Company token (required)
aws secretsmanager create-secret \
  --name konvu-company-token \
  --secret-string "comp_xxxxxxxxxxxxx" \
  --region us-east-2

# GitHub App credentials (required for broker)
aws secretsmanager create-secret \
  --name konvu-github-app-credentials \
  --description "GitHub App credentials for konvu-broker" \
  --secret-string '{
    "appId": "123456",
    "installationId": "789012",
    "privateKey": "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----"
  }' \
  --region us-east-2

# OpenAI API key (optional, for AI analysis)
aws secretsmanager create-secret \
  --name konvu-openai-key \
  --secret-string "sk-xxxxxxxxxxxxx" \
  --region us-east-2
```

### 2. Create Terraform Configuration

Create a `main.tf` file:

```hcl
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
  region = "us-east-2"
}

# Provider for ECR Public (required by module)
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

# Kubernetes provider - configured to connect to EKS cluster
# Uses try() to prevent errors during Stage 1 when cluster doesn't exist yet
provider "kubernetes" {
  host                   = try(module.konvu_onprem.cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.konvu_onprem.cluster_certificate_authority_data), "")
  token                  = try(data.aws_eks_cluster_auth.main.token, "")
}

# Helm provider - configured to connect to EKS cluster
provider "helm" {
  kubernetes {
    host                   = try(module.konvu_onprem.cluster_endpoint, "")
    cluster_ca_certificate = try(base64decode(module.konvu_onprem.cluster_certificate_authority_data), "")
    token                  = try(data.aws_eks_cluster_auth.main.token, "")
  }
}

# Get auth token for EKS cluster
data "aws_eks_cluster_auth" "main" {
  name = "konvu-onprem"
}

module "konvu_onprem" {
  source = "git::https://github.com/KonvuTeam/terraform-aws-konvu-onprem.git?ref=v1.0.0"

  # Pass provider configurations
  providers = {
    aws           = aws
    aws.us-east-1 = aws.us-east-1
    kubernetes    = kubernetes
    helm          = helm
  }

  # Basic Configuration
  aws_region   = "us-east-2"
  cluster_name = "konvu-onprem"
  backend_url  = "https://sensors.konvu.com"

  # Network Configuration
  vpc_cidr = "10.0.0.0/16"
  # Leave empty to auto-select first 2 AZs
  availability_zones = []

  # AWS Secrets Manager
  company_token_secret_name = "konvu-company-token"
  github_token_secret_name  = "konvu-github-token"
  openai_key_secret_name    = "konvu-openai-key"

  # Resource Sizing
  # Options: "small", "medium", "large"
  # - small: < 5 repos (10 concurrent jobs)
  # - medium: 5-20 repos (25 concurrent jobs)
  # - large: 20+ repos (50 concurrent jobs)
  resource_quota_preset = "medium"

  # Two-Stage Deployment Control
  # Stage 1: false (default) - Deploy AWS infrastructure only
  # Stage 2: true - Deploy Kubernetes resources
  deploy_kubernetes_resources = false

  # Tags
  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Application = "konvu-onprem"
  }
}

# Outputs
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

output "controller_namespace" {
  description = "Konvu controller namespace (null in Stage 1)"
  value       = module.konvu_onprem.controller_namespace
}
```

### 3. Deploy Stage 1 - AWS Infrastructure

Deploy the AWS infrastructure first (VPC, EKS cluster, IAM roles):

```bash
# Initialize Terraform
terraform init

# Review Stage 1 plan (AWS infrastructure only)
terraform plan

# Deploy Stage 1 (takes ~15-20 minutes)
terraform apply
```

After successful deployment, you'll see outputs like:
```
cluster_endpoint = "https://XXXXX.gr7.us-east-2.eks.amazonaws.com"
cluster_name = "konvu-onprem"
controller_namespace = null  # Will be populated in Stage 2
vpc_id = "vpc-xxxxx"
```

### 4. Deploy Stage 2 - Kubernetes Resources

Now enable Kubernetes resource deployment and apply again:

**Edit your `main.tf` and change:**
```hcl
module "konvu_onprem" {
  # ... other configuration ...

  # Change from false to true
  deploy_kubernetes_resources = true
}
```

**Then apply:**
```bash
# Review Stage 2 plan (Kubernetes resources only)
terraform plan

# Deploy Stage 2 (takes ~5-10 minutes)
terraform apply
```

After successful deployment:
```
controller_namespace = "konvu-controller"  # Now populated
```

### 5. Verify Infrastructure

```bash
# Configure kubectl
aws eks update-kubeconfig --name konvu-onprem --region us-east-2

# Check Karpenter
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter

# Check External Secrets Operator
kubectl get pods -n konvu-controller -l app.kubernetes.io/name=external-secrets

# Verify secrets are synced from AWS Secrets Manager
kubectl get externalsecrets -n konvu-controller
# All should show STATUS: SecretSynced

kubectl get secrets -n konvu-controller
# Should show: konvu-company-token, konvu-github-token, konvu-openai-key
```

### 6. Deploy Konvu Controller (Separate Step)

**After infrastructure is ready**, deploy the Konvu Controller using Helm:

> **Note**: Controller deployment is NOT included in this Terraform module. Follow the Konvu documentation for Helm-based controller installation:
>
> - [Konvu Controller Installation Guide](https://docs.konvu.com/on-prem/controller-installation)
> - Or contact support@konvu.com for deployment instructions

The infrastructure is now ready with:
- ✅ EKS cluster running
- ✅ Karpenter autoscaling configured
- ✅ External Secrets synced
- ✅ Namespace and IRSA roles prepared
- ⏳ Controller deployment (manual Helm install)

## Module Versioning

The Konvu On-Prem Infrastructure module follows [Semantic Versioning](https://semver.org/) (MAJOR.MINOR.PATCH) to ensure predictable and manageable upgrades.

### Version Scheme

Versions are structured as `MAJOR.MINOR.PATCH`, for example `1.2.3`:

- **MAJOR** (1.x.x): Breaking changes that require manual intervention or migration steps
  - Changes to required variables (removed or renamed)
  - Changes to module outputs that downstream configurations depend on
  - Significant architectural changes (e.g., VPC networking redesign)
  - Infrastructure changes that require resource recreation

- **MINOR** (x.2.x): Backward-compatible feature additions
  - New optional variables or features
  - New module outputs
  - Performance improvements
  - Non-breaking changes to Kubernetes resource configurations
  - Updates to component versions (Karpenter, External Secrets Operator, etc.)

- **PATCH** (x.x.3): Backward-compatible bug fixes
  - Bug fixes that don't change behavior
  - Documentation updates
  - Security patches
  - Minor configuration adjustments

### Finding Available Versions

Module versions are available as Git tags in the repository. Each release is tagged with semantic versioning (e.g., `v1.0.0`, `v1.0.1`).

To find available versions:

1. **Check GitHub Releases**: View all releases at https://github.com/KonvuTeam/terraform-aws-konvu-onprem/releases
2. **List tags via Git**:
   ```bash
   git ls-remote --tags https://github.com/KonvuTeam/terraform-aws-konvu-onprem.git
   ```
3. **Review Release Notes**: Each release includes detailed changelog and upgrade instructions
4. **Test Before Upgrading**: Always test version upgrades in a non-production environment first

### Upgrading Between Versions

#### PATCH Version Upgrades (e.g., 1.0.0 → 1.0.1)

PATCH upgrades are safe and straightforward:

```hcl
module "konvu_onprem" {
  # Update version from 1.0.0 to 1.0.1
  source = "git::https://github.com/KonvuTeam/terraform-aws-konvu-onprem.git?ref=v1.0.1"

  # No variable changes required
  # ...existing configuration...
}
```

Apply the upgrade:

```bash
terraform init -upgrade
terraform plan  # Review changes
terraform apply
```

#### MINOR Version Upgrades (e.g., 1.0.1 → 1.1.0)

MINOR upgrades add new features but maintain backward compatibility:

```hcl
module "konvu_onprem" {
  # Update version from 1.0.1 to 1.1.0
  source = "git::https://github.com/KonvuTeam/terraform-aws-konvu-onprem.git?ref=v1.1.0"

  # Existing variables work unchanged
  # ...existing configuration...

  # Optionally adopt new features:
  # new_optional_variable = "value"
}
```

Apply the upgrade:

```bash
terraform init -upgrade
terraform plan  # Review changes and new features
terraform apply
```

#### MAJOR Version Upgrades (e.g., 1.2.3 → 2.0.0)

MAJOR upgrades may require migration steps:

1. **Read Migration Guide**: Check the release notes for breaking changes and migration instructions
2. **Review Variable Changes**: Update any renamed or removed variables in your configuration
3. **Plan Carefully**: Use `terraform plan` to understand infrastructure changes
4. **Test First**: Always test MAJOR upgrades in a non-production environment
5. **Backup State**: Create a backup of your Terraform state before applying

```bash
# Backup your state
terraform state pull > backup-state.json

# Update module source in your configuration
# Update/remove changed variables per migration guide

# Review the upgrade plan carefully
terraform init -upgrade
terraform plan > upgrade-plan.txt

# Review the plan file before proceeding
# Apply when ready
terraform apply
```

### Version Pinning Best Practices

Always pin to a specific version tag (not `main` branch):

```hcl
# ✅ Good: Explicit version pinning
source = "git::https://github.com/KonvuTeam/terraform-aws-konvu-onprem.git?ref=v1.0.0"

# ❌ Avoid: Using branch (unpredictable)
source = "git::https://github.com/KonvuTeam/terraform-aws-konvu-onprem.git?ref=main"
```

This ensures:
- Predictable and reproducible deployments
- Controlled upgrade timing
- Easier troubleshooting with known versions

### Breaking Change Policy

Konvu commits to:

- **Advance Notice**: MAJOR version releases are announced at least 2 weeks in advance
- **Migration Documentation**: All breaking changes include detailed migration guides
- **Support Window**: Previous MAJOR versions receive security patches for 6 months after new MAJOR release
- **Gradual Deprecation**: Features are deprecated in MINOR versions before removal in MAJOR versions

## Configuration

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `aws_region` | AWS region to deploy resources | `"us-east-2"` |
| `cluster_name` | Name of the EKS cluster | `"konvu-onprem"` |
| `backend_url` | Konvu backend URL | `"https://sensors.konvu.com"` |
| `company_token_secret_name` | AWS Secrets Manager secret name for company token | `"konvu-company-token"` |
| `github_token_secret_name` | AWS Secrets Manager secret name for GitHub token | `"konvu-github-token"` |
| `openai_key_secret_name` | AWS Secrets Manager secret name for OpenAI key | `"konvu-openai-key"` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `deploy_kubernetes_resources` | Deploy Kubernetes resources (Karpenter manifests, External Secrets). Set to `false` for Stage 1 (AWS infrastructure), then `true` for Stage 2 (Kubernetes resources). | `false` |
| `vpc_cidr` | VPC CIDR block | `"10.0.0.0/16"` |
| `availability_zones` | List of AZs (empty = auto-select first 2) | `[]` |
| `kubernetes_version` | Kubernetes version | `"1.31"` |
| `resource_quota_preset` | Resource quota preset (small/medium/large) | `"medium"` |
| `enable_verbose_logging` | Enable verbose logging for debugging | `false` |

See [variables.tf](./variables.tf) for complete list and documentation.

## Outputs

| Output | Description |
|--------|-------------|
| `vpc_id` | ID of the created VPC |
| `cluster_endpoint` | EKS cluster API endpoint |
| `cluster_name` | Name of the EKS cluster |
| `cluster_certificate_authority_data` | Base64 encoded certificate for cluster access (sensitive) |
| `karpenter_node_iam_role_arn` | ARN of IAM role used by Karpenter nodes |
| `controller_service_account_role_arn` | ARN of IAM role for konvu-controller |
| `controller_namespace` | Kubernetes namespace prepared for controller |

See [outputs.tf](./outputs.tf) for complete list.

## Cost Optimization

This module is designed for cost efficiency:

### Cost Components

1. **VPC Endpoints**: ~$15-20/month
   - S3 Gateway Endpoint: FREE
   - ECR API Endpoint: ~$7/month
   - ECR DKR Endpoint: ~$7/month

2. **NAT Gateway**: ~$32-45/month (1 gateway for cost optimization)
   - Hourly charge: $0.045/hour
   - Data processing: $0.045/GB

3. **EKS Control Plane**: $73/month
   - Fixed cost per cluster

4. **Compute (Karpenter managed)**:
   - **Controller pod** (after deployment): ~$15-20/month (t3.medium, always-on)
   - **Analysis jobs**: Pay only when running
   - Uses **Spot instances** (60-90% cheaper than On-Demand)
   - Auto-scales to zero when idle
   - Consolidates underutilized nodes

5. **Total Base Cost**: ~$120-138/month (infrastructure only, before controller deployment)
   - Controller and analysis job costs scale with usage

### Reducing Costs Further

If not in use for extended periods:
```bash
# Scale down controller (after it's deployed, keeps infrastructure)
kubectl scale deployment konvu-controller -n konvu-controller --replicas=0

# Destroy everything when not needed
terraform destroy
```

## Resource Quota Presets

Control the maximum concurrent analysis capacity (applied at namespace level):

| Preset | Max Repos | Max Pods | CPU Limits | Memory Limits |
|--------|-----------|----------|------------|---------------|
| `small` | < 5 | 10 | 5 cores | 10Gi |
| `medium` | 5-20 | 25 | 15 cores | 30Gi |
| `large` | 20+ | 50 | 30 cores | 60Gi |

## Troubleshooting

### Two-Stage Deployment Issues

**Problem**: Terraform errors during Stage 1 about kubernetes provider connection

**Symptoms**:
```
Error: Failed to construct REST client
Error: Get "http://localhost/api/v1/namespaces/konvu-controller": dial tcp [::1]:80: connect: connection refused
```

**Solution**: This should not occur with the updated module configuration. Ensure:
1. Kubernetes and Helm providers use `try()` in their configuration
2. `deploy_kubernetes_resources = false` in Stage 1
3. Provider configuration includes fallback empty strings: `try(module.konvu_onprem.cluster_endpoint, "")`

**Problem**: Resources not created in Stage 2

**Symptoms**: After setting `deploy_kubernetes_resources = true` and running `terraform apply`, no new resources are created.

**Solution**:
```bash
# Verify the variable is set correctly in your configuration
grep "deploy_kubernetes_resources" main.tf

# Should show: deploy_kubernetes_resources = true

# If correct, refresh state and reapply
terraform refresh
terraform plan  # Should show ~8-10 resources to add
terraform apply
```

**Problem**: Stage 2 fails with "Secret not found" errors

**Symptoms**: ExternalSecret resources fail to sync secrets from AWS Secrets Manager.

**Solution**:
```bash
# Verify secrets exist in AWS
aws secretsmanager get-secret-value --secret-id konvu-company-token --region us-east-2
aws secretsmanager get-secret-value --secret-id konvu-github-token --region us-east-2
aws secretsmanager get-secret-value --secret-id konvu-openai-key --region us-east-2

# Check External Secrets Operator logs
kubectl logs -n konvu-controller -l app.kubernetes.io/name=external-secrets

# Verify IAM role has permissions
aws iam get-role --role-name konvu-onprem-external-secrets-operator
```

### External Secrets not syncing

Check External Secrets Operator:
```bash
kubectl get pods -n konvu-controller -l app.kubernetes.io/name=external-secrets
kubectl logs -n konvu-controller -l app.kubernetes.io/name=external-secrets

# Check ExternalSecret status
kubectl get externalsecrets -n konvu-controller
kubectl describe externalsecret konvu-company-token -n konvu-controller
```

Verify IAM role has Secrets Manager permissions:
```bash
aws secretsmanager get-secret-value --secret-id konvu-company-token --region us-east-2
```

### No nodes provisioning (after controller deployment)

Check Karpenter:
```bash
# View Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter

# Check NodePool and NodeClass
kubectl get nodepools
kubectl get ec2nodeclasses

# Verify IAM role
kubectl describe nodepool default
```

### Accessing the cluster

If you lose kubectl access:
```bash
aws eks update-kubeconfig --name konvu-onprem --region us-east-2
```

## Security Considerations

1. **Secrets Management**: All sensitive credentials stored in AWS Secrets Manager
2. **Network Isolation**: Private subnets for EKS nodes, no direct internet access
3. **IAM Roles**: IRSA (IAM Roles for Service Accounts) for pod-level permissions
4. **Encryption**: Secrets encrypted at rest in Secrets Manager
5. **Spot Instances**: Use Spot capacity pools across multiple instance types for availability

## Maintenance

### Regular maintenance tasks:

1. **Kubernetes Version Updates**: Update `kubernetes_version` annually
2. **Terraform Provider Updates**: Run `terraform init -upgrade` quarterly
3. **Review Costs**: Check AWS Cost Explorer monthly

### Backup/Disaster Recovery:

The module is stateless - configuration is in Terraform state. To recreate:
```bash
terraform apply
```

No data is stored in the cluster (all analysis results sent to Konvu backend).

## Support

For assistance with the Konvu On-Prem Infrastructure:

### Company Token Access

To obtain or renew your Konvu company token (required for controller runtime authentication):

- **Email**: support@konvu.com
- **Subject**: "Company Token Request" or "Company Token Renewal"

Include your organization name and use case in your request.

### Technical Support

For deployment issues, configuration questions, or troubleshooting:

- **Documentation**: https://docs.konvu.com
- **Email**: support@konvu.com
- **GitHub Issues**: https://github.com/KonvuTeam/terraform-aws-konvu-onprem/issues

### What to Include in Support Requests

When contacting support, please provide:

1. **Module version**: The version tag from your `source` URL (e.g., `v1.0.0`)
2. **Error messages**: Complete error output from Terraform or kubectl
3. **Logs**: Relevant logs from `terraform apply` or `kubectl logs`
4. **Configuration**: Your module configuration (sanitized - remove secrets!)

This helps us provide faster and more accurate assistance.

## License

Apache License 2.0 - Copyright © 2025 Konvu

This Terraform module is provided as part of the Konvu On-Premises offering.
