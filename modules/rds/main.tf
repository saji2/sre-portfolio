#------------------------------------------------------------------------------
# RDS Module
# PostgreSQL Multi-AZ database for task management application
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# DB Subnet Group
#------------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Database subnet group for ${var.project_name}"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

#------------------------------------------------------------------------------
# Security Group
#------------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-rds-sg"
  })
}

resource "aws_security_group_rule" "rds_ingress" {
  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_id
  security_group_id        = aws_security_group.rds.id
  description              = "Allow PostgreSQL access from EKS nodes"
}

#------------------------------------------------------------------------------
# Parameter Group
#------------------------------------------------------------------------------
resource "aws_db_parameter_group" "main" {
  name        = "${var.project_name}-pg-params"
  family      = "postgres${split(".", var.engine_version)[0]}"
  description = "Parameter group for ${var.project_name} PostgreSQL"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "1"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = var.slow_query_log_threshold
    apply_method = "pending-reboot"
  }

  tags = var.tags
}

#------------------------------------------------------------------------------
# Secrets Manager for credentials
#------------------------------------------------------------------------------
resource "random_password" "master_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "rds" {
  name                    = "${var.project_name}/rds/credentials"
  description             = "RDS PostgreSQL credentials for ${var.project_name}"
  recovery_window_in_days = var.secret_recovery_window_days

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master_password.result
    host     = aws_db_instance.main.address
    port     = var.port
    dbname   = var.database_name
    engine   = "postgres"
  })
}

#------------------------------------------------------------------------------
# RDS Instance
#------------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-postgres"

  engine                = "postgres"
  engine_version        = var.engine_version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = var.kms_key_id

  db_name  = var.database_name
  username = var.master_username
  password = random_password.master_password.result
  port     = var.port

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false

  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-postgres-final-snapshot"
  deletion_protection       = var.deletion_protection

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  enabled_cloudwatch_logs_exports = var.cloudwatch_logs_exports

  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  tags = merge(var.tags, {
    Name = "${var.project_name}-postgres"
  })
}

#------------------------------------------------------------------------------
# CloudWatch Alarms
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-rds-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_utilization_threshold
  alarm_description   = "RDS CPU utilization is high"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage_space" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-rds-free-storage-space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.free_storage_space_threshold
  alarm_description   = "RDS free storage space is low"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.project_name}-rds-database-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.database_connections_threshold
  alarm_description   = "RDS database connections are high"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = var.tags
}
