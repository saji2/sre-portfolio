#------------------------------------------------------------------------------
# SRE Portfolio - Development Environment Outputs
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# VPC
#------------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_eks_subnet_ids" {
  description = "IDs of private EKS subnets"
  value       = module.vpc.private_eks_subnet_ids
}

output "private_data_subnet_ids" {
  description = "IDs of private data subnets"
  value       = module.vpc.private_data_subnet_ids
}

#------------------------------------------------------------------------------
# EKS
#------------------------------------------------------------------------------
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "node_group_security_group_id" {
  description = "Security group ID of the node group"
  value       = module.eks.node_group_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = module.eks.oidc_provider_arn
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

#------------------------------------------------------------------------------
# RDS
#------------------------------------------------------------------------------
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
}

output "rds_address" {
  description = "RDS instance address"
  value       = module.rds.db_instance_address
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.rds.db_instance_port
}

output "rds_database_name" {
  description = "Name of the database"
  value       = module.rds.db_name
}

output "rds_secret_arn" {
  description = "ARN of the RDS credentials secret"
  value       = module.rds.secret_arn
}

#------------------------------------------------------------------------------
# ElastiCache
#------------------------------------------------------------------------------
output "redis_primary_endpoint" {
  description = "Redis primary endpoint"
  value       = module.elasticache.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "Redis reader endpoint"
  value       = module.elasticache.reader_endpoint_address
}

output "redis_port" {
  description = "Redis port"
  value       = module.elasticache.port
}

output "redis_secret_arn" {
  description = "ARN of the Redis auth token secret"
  value       = module.elasticache.secret_arn
}

#------------------------------------------------------------------------------
# Monitoring
#------------------------------------------------------------------------------
output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic"
  value       = module.monitoring.sns_topic_arn
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = module.monitoring.dashboard_name
}

output "fluent_bit_role_arn" {
  description = "ARN of the Fluent Bit IAM role"
  value       = module.monitoring.fluent_bit_role_arn
}

#------------------------------------------------------------------------------
# ECR
#------------------------------------------------------------------------------
output "ecr_api_repository_url" {
  description = "URL of the API ECR repository"
  value       = module.ecr.api_repository_url
}

output "ecr_frontend_repository_url" {
  description = "URL of the Frontend ECR repository"
  value       = module.ecr.frontend_repository_url
}
