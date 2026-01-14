#------------------------------------------------------------------------------
# ElastiCache Module
# Redis cluster for session management and caching
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Subnet Group
#------------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-redis-subnet-group"
  description = "Redis subnet group for ${var.project_name}"
  subnet_ids  = var.subnet_ids

  tags = var.tags
}

#------------------------------------------------------------------------------
# Security Group
#------------------------------------------------------------------------------
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-redis-sg"
  })
}

resource "aws_security_group_rule" "redis_ingress" {
  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_id
  security_group_id        = aws_security_group.redis.id
  description              = "Allow Redis access from EKS nodes"
}

#------------------------------------------------------------------------------
# Parameter Group
#------------------------------------------------------------------------------
resource "aws_elasticache_parameter_group" "main" {
  name        = "${var.project_name}-redis-params"
  family      = "redis${split(".", var.engine_version)[0]}"
  description = "Parameter group for ${var.project_name} Redis"

  parameter {
    name  = "maxmemory-policy"
    value = var.maxmemory_policy
  }

  parameter {
    name  = "notify-keyspace-events"
    value = var.notify_keyspace_events
  }

  tags = var.tags
}

#------------------------------------------------------------------------------
# Secrets Manager for auth token
#------------------------------------------------------------------------------
resource "random_password" "auth_token" {
  count   = var.transit_encryption_enabled ? 1 : 0
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "redis" {
  count                   = var.transit_encryption_enabled ? 1 : 0
  name                    = "${var.project_name}/redis/auth-token"
  description             = "Redis AUTH token for ${var.project_name}"
  recovery_window_in_days = var.secret_recovery_window_days

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redis" {
  count     = var.transit_encryption_enabled ? 1 : 0
  secret_id = aws_secretsmanager_secret.redis[0].id
  secret_string = jsonencode({
    auth_token = random_password.auth_token[0].result
    host       = aws_elasticache_replication_group.main.primary_endpoint_address
    port       = var.port
  })
}

#------------------------------------------------------------------------------
# ElastiCache Replication Group
#------------------------------------------------------------------------------
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.project_name}-redis"
  description          = "Redis replication group for ${var.project_name}"

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = var.port
  parameter_group_name = aws_elasticache_parameter_group.main.name

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  transit_encryption_enabled = var.transit_encryption_enabled
  auth_token                 = var.transit_encryption_enabled ? random_password.auth_token[0].result : null

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window
  maintenance_window       = var.maintenance_window

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  notification_topic_arn = var.notification_topic_arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-redis"
  })
}

#------------------------------------------------------------------------------
# CloudWatch Alarms
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-redis-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_utilization_threshold
  alarm_description   = "Redis CPU utilization is high"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    CacheClusterId = "${var.project_name}-redis-001"
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "memory_usage" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-redis-memory-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_usage_threshold
  alarm_description   = "Redis memory usage is high"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    CacheClusterId = "${var.project_name}-redis-001"
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "curr_connections" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-redis-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CurrConnections"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.connections_threshold
  alarm_description   = "Redis connections are high"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    CacheClusterId = "${var.project_name}-redis-001"
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cache_hit_rate" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-redis-cache-hit-rate"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CacheHitRate"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.cache_hit_rate_threshold
  alarm_description   = "Redis cache hit rate is low"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    CacheClusterId = "${var.project_name}-redis-001"
  }

  tags = var.tags
}
