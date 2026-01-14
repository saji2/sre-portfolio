#------------------------------------------------------------------------------
# ElastiCache Module Outputs
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
  description = "Port number for Redis"
  value       = var.port
}

output "security_group_id" {
  description = "Security group ID for the ElastiCache cluster"
  value       = aws_security_group.redis.id
}

output "subnet_group_name" {
  description = "Name of the ElastiCache subnet group"
  value       = aws_elasticache_subnet_group.main.name
}

output "parameter_group_name" {
  description = "Name of the ElastiCache parameter group"
  value       = aws_elasticache_parameter_group.main.name
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret (if transit encryption is enabled)"
  value       = var.transit_encryption_enabled ? aws_secretsmanager_secret.redis[0].arn : null
}

output "secret_name" {
  description = "Name of the Secrets Manager secret (if transit encryption is enabled)"
  value       = var.transit_encryption_enabled ? aws_secretsmanager_secret.redis[0].name : null
}
