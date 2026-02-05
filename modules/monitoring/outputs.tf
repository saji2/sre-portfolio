#------------------------------------------------------------------------------
# SNS Topic Outputs
#------------------------------------------------------------------------------
output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS alerts topic"
  value       = aws_sns_topic.alerts.name
}

#------------------------------------------------------------------------------
# CloudWatch Dashboard Outputs
#------------------------------------------------------------------------------
output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_arn
}

#------------------------------------------------------------------------------
# CloudWatch Log Group Outputs
#------------------------------------------------------------------------------
output "eks_cluster_log_group_name" {
  description = "Name of the EKS cluster log group"
  value       = aws_cloudwatch_log_group.eks_cluster.name
}

output "eks_cluster_log_group_arn" {
  description = "ARN of the EKS cluster log group for IAM policies"
  value       = aws_cloudwatch_log_group.eks_cluster.arn
}

output "application_log_group_name" {
  description = "Name of the application log group"
  value       = aws_cloudwatch_log_group.application.name
}

output "application_log_group_arn" {
  description = "ARN of the application log group for IAM policies"
  value       = aws_cloudwatch_log_group.application.arn
}

output "frontend_log_group_name" {
  description = "Name of the frontend log group"
  value       = aws_cloudwatch_log_group.frontend.name
}

output "frontend_log_group_arn" {
  description = "ARN of the frontend log group for IAM policies"
  value       = aws_cloudwatch_log_group.frontend.arn
}

output "kube_system_log_group_name" {
  description = "Name of the kube-system log group"
  value       = aws_cloudwatch_log_group.kube_system.name
}

output "kube_system_log_group_arn" {
  description = "ARN of the kube-system log group for IAM policies"
  value       = aws_cloudwatch_log_group.kube_system.arn
}

#------------------------------------------------------------------------------
# Fluent Bit IAM Role Outputs
#------------------------------------------------------------------------------
# Note: Returns null when create_fluent_bit_role is false. Use try() or coalesce() if needed.
output "fluent_bit_role_arn" {
  description = "ARN of the Fluent Bit IAM role (null if not created)"
  value       = var.create_fluent_bit_role ? aws_iam_role.fluent_bit[0].arn : null
}

output "fluent_bit_role_name" {
  description = "Name of the Fluent Bit IAM role (null if not created)"
  value       = var.create_fluent_bit_role ? aws_iam_role.fluent_bit[0].name : null
}
