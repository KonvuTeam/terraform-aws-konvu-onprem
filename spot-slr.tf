## EC2 Spot Service-Linked Role
## Required for Karpenter to provision spot instances
## AWS creates this role automatically on first spot instance request,
## but explicit creation prevents permission errors during Karpenter scale-up
##
## NOTE: If this role already exists in your account, Terraform will fail with
## "role already exists" error. In that case, either:
##   1. Import the existing role: terraform import 'aws_iam_service_linked_role.spot[0]' arn:aws:iam::ACCOUNT:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot
##   2. Set enable_spot_service_linked_role = false and skip creation
resource "aws_iam_service_linked_role" "spot" {
  count = var.enable_spot_service_linked_role ? 1 : 0

  aws_service_name = "spot.amazonaws.com"
  description      = "Service-linked role for EC2 Spot instances (required by Karpenter)"

  tags = merge(
    {
      Name = "EC2SpotServiceLinkedRole"
    },
    var.tags
  )
}
