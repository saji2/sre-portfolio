#------------------------------------------------------------------------------
# Monitoring Module Variables
#------------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
}

variable "rds_instance_identifier" {
  description = "RDS instance identifier for dashboard"
  type        = string
  default     = ""
}

variable "elasticache_cluster_id" {
  description = "ElastiCache cluster ID for dashboard"
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for alarms"
  type        = string
  default     = ""
}

variable "alb_target_group_arn_suffix" {
  description = "ALB Target Group ARN suffix for alarms"
  type        = string
  default     = ""
}

variable "create_eks_alarms" {
  description = "Create EKS-related CloudWatch alarms"
  type        = bool
  default     = true
}

variable "create_alb_alarms" {
  description = "Create ALB-related CloudWatch alarms"
  type        = bool
  default     = false
}

variable "alb_5xx_threshold" {
  description = "Threshold for ALB 5xx errors"
  type        = number
  default     = 10
}

variable "alb_response_time_threshold" {
  description = "Threshold for ALB response time in seconds (P95)"
  type        = number
  default     = 0.5
}

variable "create_fluent_bit_role" {
  description = "Create IAM role for Fluent Bit"
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "URL of the OIDC provider for IRSA"
  type        = string
  default     = ""
}

variable "fluent_bit_namespace" {
  description = "Kubernetes namespace for Fluent Bit"
  type        = string
  default     = "amazon-cloudwatch"
}

variable "fluent_bit_service_account" {
  description = "Kubernetes service account for Fluent Bit"
  type        = string
  default     = "fluent-bit"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
