# Konvu On-Prem Controller Module - Secrets Management
# Uses External Secrets Operator to sync AWS Secrets Manager secrets to Kubernetes

## External Secrets Operator IAM Role for Controller (IRSA)
resource "aws_iam_role" "external_secrets_operator" {
  name = "${var.cluster_name}-external-secrets-operator"

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
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:konvu-controller:external-secrets"
            "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    {
      Name = "${var.cluster_name}-external-secrets-operator"
    },
    var.tags
  )
}

## External Secrets Operator IAM Role for Broker (IRSA)
resource "aws_iam_role" "broker_external_secrets_operator" {
  name = "${var.cluster_name}-broker-external-secrets-operator"

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
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:konvu-broker:external-secrets"
            "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    {
      Name = "${var.cluster_name}-broker-external-secrets-operator"
    },
    var.tags
  )
}

## IAM Policy for Controller External Secrets Operator
## Grants access to: company token, OpenAI key
data "aws_iam_policy_document" "controller_external_secrets_policy" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.company_token_secret_name}*",
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.openai_key_secret_name}*",
    ]
  }
}

resource "aws_iam_policy" "controller_external_secrets_access" {
  name        = "${var.cluster_name}-controller-external-secrets-access"
  description = "Policy for controller External Secrets Operator to access AWS Secrets Manager"
  policy      = data.aws_iam_policy_document.controller_external_secrets_policy.json

  tags = merge(
    {
      Name = "${var.cluster_name}-controller-external-secrets-access"
    },
    var.tags
  )
}

resource "aws_iam_role_policy_attachment" "controller_external_secrets_access" {
  role       = aws_iam_role.external_secrets_operator.name
  policy_arn = aws_iam_policy.controller_external_secrets_access.arn
}

## IAM Policy for Broker External Secrets Operator
## Grants access to: company token, GitHub App credentials
data "aws_iam_policy_document" "broker_external_secrets_policy" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.company_token_secret_name}*",
      "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.github_app_credentials_secret_name}*",
    ]
  }
}

resource "aws_iam_policy" "broker_external_secrets_access" {
  name        = "${var.cluster_name}-broker-external-secrets-access"
  description = "Policy for broker External Secrets Operator to access AWS Secrets Manager"
  policy      = data.aws_iam_policy_document.broker_external_secrets_policy.json

  tags = merge(
    {
      Name = "${var.cluster_name}-broker-external-secrets-access"
    },
    var.tags
  )
}

resource "aws_iam_role_policy_attachment" "broker_external_secrets_access" {
  role       = aws_iam_role.broker_external_secrets_operator.name
  policy_arn = aws_iam_policy.broker_external_secrets_access.arn
}

## External Secrets Operator Helm Release
## Deployed in Stage 2 in konvu-controller namespace (controlled by deploy_kubernetes_resources variable)
resource "helm_release" "external_secrets" {
  count = var.deploy_kubernetes_resources ? 1 : 0

  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.20.4" # Using latest 0.x stable version
  namespace  = kubernetes_namespace.konvu_controller[0].metadata[0].name

  create_namespace = false # Namespace already created
  wait             = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_secrets_operator.arn
  }

  depends_on = [
    aws_eks_cluster.main,
    helm_release.karpenter[0],
    kubernetes_namespace.konvu_controller[0],
  ]
}

## External Secrets Operator Helm Release for Broker
## Deployed in Stage 2 in konvu-broker namespace (controlled by deploy_kubernetes_resources variable)
resource "helm_release" "broker_external_secrets" {
  count = var.deploy_kubernetes_resources ? 1 : 0

  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.20.4" # Using latest 0.x stable version
  namespace  = kubernetes_namespace.konvu_broker[0].metadata[0].name

  create_namespace = false # Namespace already created
  wait             = true

  set {
    name  = "installCRDs"
    value = var.broker_install_crds ? "true" : "false"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.broker_external_secrets_operator.arn
  }

  depends_on = [
    aws_eks_cluster.main,
    helm_release.karpenter[0],
    kubernetes_namespace.konvu_broker[0],
  ]
}

## Konvu Controller Namespace
## Deployed in Stage 2 after cluster is created (controlled by deploy_kubernetes_resources variable)
resource "kubernetes_namespace" "konvu_controller" {
  count = var.deploy_kubernetes_resources ? 1 : 0

  metadata {
    name = "konvu-controller"

    labels = {
      name = "konvu-controller"
    }
  }

  depends_on = [
    aws_eks_cluster.main,
    helm_release.karpenter[0],
  ]
}

## Konvu Broker Namespace
## Deployed in Stage 2 after cluster is created (controlled by deploy_kubernetes_resources variable)
resource "kubernetes_namespace" "konvu_broker" {
  count = var.deploy_kubernetes_resources ? 1 : 0

  metadata {
    name = "konvu-broker"

    labels = {
      name = "konvu-broker"
    }
  }

  depends_on = [
    aws_eks_cluster.main,
    helm_release.karpenter[0],
  ]
}

## SecretStore - Configures connection to AWS Secrets Manager
## Deployed in Stage 3 after External Secrets CRDs are installed (controlled by deploy_kubernetes_manifests variable)
resource "kubernetes_manifest" "secret_store" {
  count = var.deploy_kubernetes_manifests ? 1 : 0

  manifest = yamldecode(<<-YAML
    apiVersion: external-secrets.io/v1
    kind: SecretStore
    metadata:
      name: aws-secrets-manager
      namespace: konvu-controller
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${var.aws_region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets
  YAML
  )

  depends_on = [
    helm_release.external_secrets[0],
    kubernetes_namespace.konvu_controller[0],
  ]
}

## SecretStore for Broker - Configures connection to AWS Secrets Manager
## Deployed in Stage 3 after External Secrets CRDs are installed (controlled by deploy_kubernetes_manifests variable)
resource "kubernetes_manifest" "broker_secret_store" {
  count = var.deploy_kubernetes_manifests ? 1 : 0

  manifest = yamldecode(<<-YAML
    apiVersion: external-secrets.io/v1
    kind: SecretStore
    metadata:
      name: aws-secrets-manager
      namespace: konvu-broker
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${var.aws_region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets
  YAML
  )

  depends_on = [
    helm_release.broker_external_secrets[0],
    kubernetes_namespace.konvu_broker[0],
  ]
}

## ExternalSecret - Syncs company token from AWS Secrets Manager
## Deployed in Stage 3 after SecretStore is created (controlled by deploy_kubernetes_manifests variable)
resource "kubernetes_manifest" "company_token_secret" {
  count = var.deploy_kubernetes_manifests ? 1 : 0

  manifest = yamldecode(<<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: konvu-company-token
      namespace: konvu-controller
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-secrets-manager
        kind: SecretStore
      target:
        name: konvu-company-token
        creationPolicy: Owner
      data:
        - secretKey: company-token
          remoteRef:
            key: ${var.company_token_secret_name}
  YAML
  )

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.secret_store[0],
  ]
}

## ExternalSecret - Syncs company token to broker namespace
## Deployed in Stage 3 after SecretStore is created (controlled by deploy_kubernetes_manifests variable)
resource "kubernetes_manifest" "broker_company_token_secret" {
  count = var.deploy_kubernetes_manifests ? 1 : 0

  manifest = yamldecode(<<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: konvu-company-token
      namespace: konvu-broker
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-secrets-manager
        kind: SecretStore
      target:
        name: konvu-company-token
        creationPolicy: Owner
      data:
        - secretKey: company-token
          remoteRef:
            key: ${var.company_token_secret_name}
  YAML
  )

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.broker_secret_store[0],
  ]
}

## ExternalSecret - Syncs GitHub App credentials from AWS Secrets Manager
## Deployed in Stage 3 after SecretStore is created (controlled by deploy_kubernetes_manifests variable)
## Note: Creates secret named konvu-git-credentials (required by konvu-broker for repository syncing)
## Controller receives git credentials in commands (not from this secret)
resource "kubernetes_manifest" "broker_github_app_secret" {
  count = var.deploy_kubernetes_manifests ? 1 : 0

  manifest = yamldecode(<<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: konvu-git-credentials
      namespace: konvu-broker
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-secrets-manager
        kind: SecretStore
      target:
        name: konvu-git-credentials
        creationPolicy: Owner
      dataFrom:
        - extract:
            key: ${var.github_app_credentials_secret_name}
            rewrite:
              - regexp:
                  source: "(.*)"
                  target: "github-app-$$1"
  YAML
  )

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.broker_secret_store[0],
    kubernetes_namespace.konvu_broker[0],
  ]
}

## ExternalSecret - Syncs OpenAI key from AWS Secrets Manager
## Deployed in Stage 3 after SecretStore is created (controlled by deploy_kubernetes_manifests variable)
resource "kubernetes_manifest" "openai_key_secret" {
  count = var.deploy_kubernetes_manifests ? 1 : 0

  manifest = yamldecode(<<-YAML
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: konvu-ai-credentials
      namespace: konvu-controller
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-secrets-manager
        kind: SecretStore
      target:
        name: konvu-ai-credentials
        creationPolicy: Owner
      data:
        - secretKey: openai-api-key
          remoteRef:
            key: ${var.openai_key_secret_name}
  YAML
  )

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.secret_store[0],
  ]
}
