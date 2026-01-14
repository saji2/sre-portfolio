#------------------------------------------------------------------------------
# EKS Module Outputs
#------------------------------------------------------------------------------

output "cluster_id" {
  description = "ID of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "node_group_security_group_id" {
  description = "Security group ID of the EKS node group"
  value       = aws_security_group.node_group.id
}

output "node_group_role_arn" {
  description = "ARN of the IAM role for the node group"
  value       = aws_iam_role.node_group.arn
}

output "node_group_role_name" {
  description = "Name of the IAM role for the node group"
  value       = aws_iam_role.node_group.name
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.cluster.url
}

output "aws_lb_controller_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller"
  value       = var.enable_aws_lb_controller ? aws_iam_role.aws_lb_controller[0].arn : null
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the IAM role for Cluster Autoscaler"
  value       = var.enable_cluster_autoscaler ? aws_iam_role.cluster_autoscaler[0].arn : null
}

output "cluster_primary_security_group_id" {
  description = "Cluster primary security group ID created by EKS"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
