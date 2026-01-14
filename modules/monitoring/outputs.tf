#------------------------------------------------------------------------------
# Monitoring Module Outputs
#------------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.name
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_arn
}

output "eks_cluster_log_group_name" {
  description = "Name of the EKS cluster log group"
  value       = aws_cloudwatch_log_group.eks_cluster.name
}

output "application_log_group_name" {
  description = "Name of the application log group"
  value       = aws_cloudwatch_log_group.application.name
}

output "frontend_log_group_name" {
  description = "Name of the frontend log group"
  value       = aws_cloudwatch_log_group.frontend.name
}

output "fluent_bit_role_arn" {
  description = "ARN of the Fluent Bit IAM role"
  value       = var.create_fluent_bit_role ? aws_iam_role.fluent_bit[0].arn : null
}
