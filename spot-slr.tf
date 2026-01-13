# EC2 Spot Service-Linked Role
# Required for Karpenter to launch spot instances

## EC2 Spot Service-Linked Role
## This role is required for Karpenter to provision spot instances
## AWS creates this role automatically when first spot instance is requested,
## but we create it explicitly to avoid permission errors
resource "aws_iam_service_linked_role" "spot" {
  count = var.enable_spot_instances ? 1 : 0

  aws_service_name = "spot.amazonaws.com"
  description      = "Service-linked role for EC2 Spot instances (required by Karpenter)"

  # Ignore if role already exists
  lifecycle {
    ignore_changes = [
      aws_service_name,
      description,
    ]
  }

  tags = merge(
    {
      Name = "EC2SpotServiceLinkedRole"
    },
    var.tags
  )
}
