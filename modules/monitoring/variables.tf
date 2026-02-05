#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

#------------------------------------------------------------------------------
# SNS Configuration
#------------------------------------------------------------------------------
variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# CloudWatch Log Configuration
#------------------------------------------------------------------------------
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the CloudWatch Logs supported values: 0 (never expire), 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653 days."
  }
}

#------------------------------------------------------------------------------
# Resource Identifiers for Dashboard
#------------------------------------------------------------------------------
variable "rds_instance_identifier" {
  description = "RDS instance identifier for dashboard metrics"
  type        = string
  default     = ""
}

variable "elasticache_cluster_id" {
  description = "ElastiCache cluster ID for dashboard metrics"
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for dashboard and alarms"
  type        = string
  default     = ""
}

variable "alb_target_group_arn_suffix" {
  description = "ALB target group ARN suffix for alarms"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# Alarm Configuration
#------------------------------------------------------------------------------
variable "create_eks_alarms" {
  description = "Create EKS CloudWatch alarms"
  type        = bool
  default     = true
}

variable "create_alb_alarms" {
  description = "Create ALB CloudWatch alarms"
  type        = bool
  default     = true
}

variable "alb_5xx_threshold" {
  description = "Threshold for ALB 5xx error alarm"
  type        = number
  default     = 10

  validation {
    condition     = var.alb_5xx_threshold >= 0
    error_message = "alb_5xx_threshold must be a non-negative number."
  }
}

variable "alb_response_time_threshold" {
  description = "Threshold for ALB response time alarm (seconds)"
  type        = number
  default     = 2

  validation {
    condition     = var.alb_response_time_threshold > 0
    error_message = "alb_response_time_threshold must be a positive number."
  }
}

#------------------------------------------------------------------------------
# Fluent Bit IRSA Configuration
#------------------------------------------------------------------------------
variable "create_fluent_bit_role" {
  description = "Create IAM role for Fluent Bit"
  type        = bool
  default     = false
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for EKS. Required when create_fluent_bit_role is true."
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "OIDC provider URL for EKS. Required when create_fluent_bit_role is true."
  type        = string
  default     = ""
}

variable "fluent_bit_namespace" {
  description = "Kubernetes namespace for Fluent Bit"
  type        = string
  default     = "amazon-cloudwatch"
}

variable "fluent_bit_service_account" {
  description = "Kubernetes service account name for Fluent Bit"
  type        = string
  default     = "fluent-bit"
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------
variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
