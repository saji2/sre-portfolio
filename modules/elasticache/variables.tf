#------------------------------------------------------------------------------
# ElastiCache Module Variables
#------------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
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
  description = "Number of cache clusters (primary + replicas)"
  type        = number
  default     = 2
}

variable "automatic_failover_enabled" {
  description = "Enable automatic failover"
  type        = bool
  default     = true
}

variable "multi_az_enabled" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = true
}

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

variable "snapshot_retention_limit" {
  description = "Number of days to retain snapshots"
  type        = number
  default     = 7
}

variable "snapshot_window" {
  description = "Daily time range for snapshots (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC)"
  type        = string
  default     = "mon:04:00-mon:05:00"
}

variable "auto_minor_version_upgrade" {
  description = "Enable auto minor version upgrade"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes immediately"
  type        = bool
  default     = false
}

variable "maxmemory_policy" {
  description = "Redis maxmemory policy"
  type        = string
  default     = "volatile-lru"
}

variable "notify_keyspace_events" {
  description = "Keyspace event notifications"
  type        = string
  default     = ""
}

variable "secret_recovery_window_days" {
  description = "Number of days before secret can be deleted"
  type        = number
  default     = 7
}

variable "notification_topic_arn" {
  description = "ARN of SNS topic for notifications"
  type        = string
  default     = null
}

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for Redis"
  type        = bool
  default     = true
}

variable "cpu_utilization_threshold" {
  description = "CPU utilization threshold for alarm"
  type        = number
  default     = 80
}

variable "memory_usage_threshold" {
  description = "Memory usage percentage threshold for alarm"
  type        = number
  default     = 80
}

variable "connections_threshold" {
  description = "Connections threshold for alarm"
  type        = number
  default     = 1000
}

variable "cache_hit_rate_threshold" {
  description = "Cache hit rate threshold for alarm (low hit rate is concerning)"
  type        = number
  default     = 0.8
}

variable "alarm_actions" {
  description = "List of ARNs for alarm actions (SNS topics)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
