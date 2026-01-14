# Konvu On-Prem Controller Module - EKS Configuration

## EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
    security_group_ids      = [aws_security_group.cluster.id]
  }

  access_config {
    authentication_mode                         = "CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
  ]

  tags = merge(
    {
      Name = var.cluster_name
    },
    var.tags
  )

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
  ]
}

## AWS Auth ConfigMap for Cluster Administrator Access
## This grants cluster admin access via the traditional aws-auth ConfigMap method
## which works with AWS SSO roles (unlike EKS access entries)
resource "kubernetes_config_map_v1" "aws_auth" {
  count = var.deploy_kubernetes_resources && length(var.cluster_admin_role_arns) > 0 ? 1 : 0

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode(concat(
      # Managed node group role (if enabled)
      var.enable_managed_node_group ? [{
        rolearn  = aws_iam_role.node_group[0].arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }] : [],
      # Karpenter node role
      [{
        rolearn  = module.karpenter.node_iam_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }],
      # Admin roles
      [for role_arn in var.cluster_admin_role_arns : {
        rolearn  = role_arn
        username = "admin:{{SessionName}}"
        groups   = ["system:masters"]
      }]
    ))
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.system, # Wait for node group to exist
  ]
}

## OIDC Provider for IRSA (IAM Roles for Service Accounts)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(
    {
      Name = "${var.cluster_name}-eks-oidc"
    },
    var.tags
  )
}

locals {
  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn
  oidc_provider_url = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

## Managed Node Group for Bootstrap
## Creates initial nodes to host CoreDNS, Karpenter, and other system pods
## This solves the bootstrap chicken-egg problem where Karpenter needs nodes to run on
resource "aws_eks_node_group" "system" {
  count = var.enable_managed_node_group ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-system"
  node_role_arn   = aws_iam_role.node_group[0].arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = [var.system_node_instance_type]
  capacity_type  = "ON_DEMAND" # Use On-Demand for reliability of system pods

  scaling_config {
    desired_size = var.system_node_count
    max_size     = var.system_node_count
    min_size     = var.system_node_count
  }

  labels = {
    "workload-type" = "system"
    "managed-by"    = "terraform"
  }

  # No taints - allow all pods to schedule on these nodes
  # This is intentional to allow CoreDNS, Karpenter, and other system pods to run

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = merge(
    {
      Name                     = "${var.cluster_name}-system-node-group"
      "karpenter.sh/discovery" = var.cluster_name
    },
    var.tags
  )
}

## EKS Add-ons
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  addon_version            = data.aws_eks_addon_version.coredns.version
  resolve_conflicts        = "OVERWRITE"
  preserve                 = false
  service_account_role_arn = null

  depends_on = [
    aws_eks_node_group.system, # Wait for managed nodes to exist before installing CoreDNS
  ]
}

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  addon_version     = data.aws_eks_addon_version.vpc_cni.version
  resolve_conflicts = "OVERWRITE"
  preserve          = false
}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"

  addon_version     = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts = "OVERWRITE"
  preserve          = false
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

resource "aws_eks_addon" "eks_pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"

  addon_version     = data.aws_eks_addon_version.eks_pod_identity_agent.version
  resolve_conflicts = "OVERWRITE"
  preserve          = false
}

data "aws_eks_addon_version" "eks_pod_identity_agent" {
  addon_name         = "eks-pod-identity-agent"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

## Karpenter Module for Node Autoscaling
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "= 20.36.0"

  cluster_name = aws_eks_cluster.main.name

  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true

  # Disable access entry creation (incompatible with CONFIG_MAP authentication mode)
  create_access_entry = false

  # Attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = merge(
    {
      "used-by" = "karpenter"
    },
    var.tags
  )
}

## ECR Public Authorization Token (for Karpenter Helm charts)
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.us-east-1
}

## Karpenter CRDs Helm Release
## Deployed in Stage 2 after cluster is created (controlled by deploy_kubernetes_resources variable)
resource "helm_release" "karpenter_crds" {
  count = var.deploy_kubernetes_resources ? 1 : 0

  name                = "karpenter-crds"
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter-crd"
  version             = "1.4.0"
  namespace           = "kube-system"
  create_namespace    = false
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
}

## Karpenter Controller Helm Release
## Deployed in Stage 2 after cluster is created (controlled by deploy_kubernetes_resources variable)
resource "helm_release" "karpenter" {
  count = var.deploy_kubernetes_resources ? 1 : 0

  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "1.4.0"
  wait                = false

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${aws_eks_cluster.main.name}
      clusterEndpoint: ${aws_eks_cluster.main.endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]

  depends_on = [
    helm_release.karpenter_crds[0],
    module.karpenter,
  ]
}

## Karpenter EC2NodeClass
## Deployed in Stage 3 after Karpenter CRDs are installed (needed for initial node bootstrapping)
resource "kubernetes_manifest" "karpenter_node_class" {
  count = var.deploy_kubernetes_manifests ? 1 : 0

  manifest = yamldecode(<<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiFamily: AL2023
      amiSelectorTerms:
        - alias: al2023@latest
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${aws_eks_cluster.main.name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${aws_eks_cluster.main.name}
        - id: ${aws_eks_cluster.main.vpc_config[0].cluster_security_group_id}
      tags:
        karpenter.sh/discovery: ${aws_eks_cluster.main.name}
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 100Gi
            volumeType: gp3
  YAML
  )

  depends_on = [
    helm_release.karpenter_crds[0],
  ]
}

## Karpenter NodePool
## Deployed in Stage 3 after Karpenter CRDs are installed (needed for initial node bootstrapping)
resource "kubernetes_manifest" "karpenter_node_pool" {
  count = var.deploy_kubernetes_manifests ? 1 : 0

  manifest = yamldecode(<<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            name: default
            group: karpenter.k8s.aws
            kind: EC2NodeClass
          requirements:
            - key: "karpenter.k8s.aws/instance-category"
              operator: In
              values: ["c", "m", "r"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot"]
            - key: "kubernetes.io/arch"
              operator: In
              values: ["amd64"]
      limits:
        cpu: 100
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 3m
  YAML
  )

  depends_on = [
    kubernetes_manifest.karpenter_node_class[0],
  ]
}

## IAM Role for Konvu Controller Service Account (IRSA)
resource "aws_iam_role" "controller_service_account" {
  name = "${var.cluster_name}-konvu-controller-sa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:konvu-controller:konvu-controller"
            "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    {
      Name = "${var.cluster_name}-konvu-controller-sa"
    },
    var.tags
  )
}

## IAM Policy for Konvu Controller to Access Secrets Manager
## Controller only needs company token and OpenAI key (not git credentials)
data "aws_iam_policy_document" "controller_secrets_policy" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.company_token_secret_name}*",
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.openai_key_secret_name}*",
    ]
  }
}

resource "aws_iam_policy" "controller_secrets_access" {
  name        = "${var.cluster_name}-konvu-controller-secrets"
  description = "Policy for konvu-controller to access AWS Secrets Manager"
  policy      = data.aws_iam_policy_document.controller_secrets_policy.json

  tags = merge(
    {
      Name = "${var.cluster_name}-konvu-controller-secrets"
    },
    var.tags
  )
}

resource "aws_iam_role_policy_attachment" "controller_secrets_access" {
  role       = aws_iam_role.controller_service_account.name
  policy_arn = aws_iam_policy.controller_secrets_access.arn
}

## IAM Role for Konvu Broker Service Account (IRSA)
## Allows broker to access AWS Secrets Manager for GitHub App credentials
resource "aws_iam_role" "broker_service_account" {
  name = "${var.cluster_name}-konvu-broker-sa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:konvu-broker:konvu-broker"
            "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    {
      Name = "${var.cluster_name}-konvu-broker-sa"
    },
    var.tags
  )
}

## IAM Policy for Konvu Broker to Access Secrets Manager
data "aws_iam_policy_document" "broker_secrets_policy" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.company_token_secret_name}*",
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.github_app_credentials_secret_name}*",
    ]
  }
}

resource "aws_iam_policy" "broker_secrets_access" {
  name        = "${var.cluster_name}-konvu-broker-secrets"
  description = "Policy for konvu-broker to access AWS Secrets Manager"
  policy      = data.aws_iam_policy_document.broker_secrets_policy.json

  tags = merge(
    {
      Name = "${var.cluster_name}-konvu-broker-secrets"
    },
    var.tags
  )
}

resource "aws_iam_role_policy_attachment" "broker_secrets_access" {
  role       = aws_iam_role.broker_service_account.name
  policy_arn = aws_iam_policy.broker_secrets_access.arn
}

# NOTE: Kubernetes and Helm providers must be configured in the calling module
# See the README.md for example configuration
