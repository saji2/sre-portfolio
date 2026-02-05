#------------------------------------------------------------------------------
# ECR Module Outputs
#------------------------------------------------------------------------------

output "api_repository_url" {
  description = "URL of the API ECR repository"
  value       = aws_ecr_repository.api.repository_url
}

output "api_repository_arn" {
  description = "ARN of the API ECR repository"
  value       = aws_ecr_repository.api.arn
}

output "frontend_repository_url" {
  description = "URL of the Frontend ECR repository"
  value       = aws_ecr_repository.frontend.repository_url
}

output "frontend_repository_arn" {
  description = "ARN of the Frontend ECR repository"
  value       = aws_ecr_repository.frontend.arn
}
