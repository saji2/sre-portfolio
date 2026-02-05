#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ElastiCache will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ElastiCache subnet group"
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group ID allowed to access Redis"
  type        = string
}

#------------------------------------------------------------------------------
# Engine Configuration
#------------------------------------------------------------------------------
variable "engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (nodes) in the replication group. Must be >= 2 when automatic_failover_enabled or multi_az_enabled is true."
  type        = number
  default     = 2

  validation {
    condition     = var.num_cache_clusters >= 1
    error_message = "num_cache_clusters must be at least 1."
  }
}

variable "automatic_failover_enabled" {
  description = "Enable automatic failover. Requires num_cache_clusters >= 2."
  type        = bool
  default     = true
}

variable "multi_az_enabled" {
  description = "Enable Multi-AZ. Requires num_cache_clusters >= 2."
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Parameter Group Settings
#------------------------------------------------------------------------------
variable "maxmemory_policy" {
  description = "Redis maxmemory policy"
  type        = string
  default     = "volatile-lru"
}

variable "notify_keyspace_events" {
  description = "Keyspace notification events"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# Security Settings
#------------------------------------------------------------------------------
variable "at_rest_encryption_enabled" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = "Enable encryption in transit"
  type        = bool
  default     = true
}

variable "secret_recovery_window_days" {
  description = "Number of days to retain secret before permanent deletion"
  type        = number
  default     = 7
}

#------------------------------------------------------------------------------
# Maintenance Settings
#------------------------------------------------------------------------------
variable "snapshot_retention_limit" {
  description = "Number of days to retain automatic snapshots"
  type        = number
  default     = 7
}

variable "snapshot_window" {
  description = "Daily time range for snapshots in UTC (format: HH:MM-HH:MM). Must NOT overlap with maintenance_window. Default ends 30 min before maintenance starts."
  type        = string
  default     = "02:30-03:30"
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC (format: day:HH:MM-day:HH:MM). Must NOT overlap with snapshot_window. Default starts 30 min after snapshot ends."
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes immediately"
  type        = bool
  default     = false
}

variable "notification_topic_arn" {
  description = "SNS topic ARN for ElastiCache notifications"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# CloudWatch Alarms
#------------------------------------------------------------------------------
variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for Redis"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs for alarm actions"
  type        = list(string)
  default     = []
}

variable "cpu_utilization_threshold" {
  description = "CPU utilization threshold for alarm (percentage, 0-100)"
  type        = number
  default     = 75

  validation {
    condition     = var.cpu_utilization_threshold >= 0 && var.cpu_utilization_threshold <= 100
    error_message = "cpu_utilization_threshold must be between 0 and 100."
  }
}

variable "memory_usage_threshold" {
  description = "Memory usage threshold for alarm (percentage, 0-100)"
  type        = number
  default     = 75

  validation {
    condition     = var.memory_usage_threshold >= 0 && var.memory_usage_threshold <= 100
    error_message = "memory_usage_threshold must be between 0 and 100."
  }
}

variable "connections_threshold" {
  description = "Connections threshold for alarm"
  type        = number
  default     = 1000

  validation {
    condition     = var.connections_threshold > 0
    error_message = "connections_threshold must be a positive number."
  }
}

variable "cache_hit_rate_threshold" {
  description = "Cache hit rate threshold for alarm; alarm fires when hit rate falls below this percentage (0-100)"
  type        = number
  default     = 80

  validation {
    condition     = var.cache_hit_rate_threshold >= 0 && var.cache_hit_rate_threshold <= 100
    error_message = "cache_hit_rate_threshold must be between 0 and 100."
  }
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
