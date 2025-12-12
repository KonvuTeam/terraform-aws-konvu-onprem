  # Complete Deployment Example

  This example shows a complete Konvu On-Prem deployment with all configuration options.

  ## Prerequisites

  1. AWS credentials configured
  2. AWS Secrets Manager secrets created:
     - `konvu-company-token`
     - `konvu-github-token`
     - `konvu-openai-key`

  ## Usage

  1. Copy the example tfvars:
     ```bash
     cp terraform.tfvars.example terraform.tfvars

  2. Edit terraform.tfvars with your values
  3. Deploy Stage 1 (AWS infrastructure):
  terraform init
  terraform plan
  terraform apply
  4. Deploy Stage 2 (Kubernetes resources):
  Edit terraform.tfvars:
  deploy_kubernetes_resources = true

  4. Then apply:
  terraform plan
  terraform apply
  5. Verify deployment:
  aws eks update-kubeconfig --name konvu-production --region us-east-2
  kubectl get pods -n konvu-controller
