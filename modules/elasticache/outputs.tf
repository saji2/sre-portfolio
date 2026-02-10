#------------------------------------------------------------------------------
# ElastiCache Replication Group Outputs
#------------------------------------------------------------------------------
output "replication_group_id" {
  description = "ID of the ElastiCache replication group"
  value       = aws_elasticache_replication_group.main.id
}

output "replication_group_arn" {
  description = "ARN of the ElastiCache replication group"
  value       = aws_elasticache_replication_group.main.arn
}

output "primary_endpoint_address" {
  description = "Primary endpoint address of the replication group"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint address of the replication group"
  value       = aws_elasticache_replication_group.main.reader_endpoint_address
}

output "port" {
  description = "Port of the ElastiCache cluster"
  value       = var.port
}

#------------------------------------------------------------------------------
# Security Group Outputs
#------------------------------------------------------------------------------
output "security_group_id" {
  description = "Security group ID of the ElastiCache cluster"
  value       = aws_security_group.redis.id
}

#------------------------------------------------------------------------------
# Secrets Manager Outputs
#------------------------------------------------------------------------------
output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing Redis auth token"
  value       = var.transit_encryption_enabled ? aws_secretsmanager_secret.redis[0].arn : null
  sensitive   = true
}

output "secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = var.transit_encryption_enabled ? aws_secretsmanager_secret.redis[0].name : null
  sensitive   = true
}
