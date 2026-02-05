#------------------------------------------------------------------------------
# ECR Module Variables
#------------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_/-]*$", var.project_name)) && length(var.project_name) >= 2 && length(var.project_name) <= 256
    error_message = "Project name must be 2-256 characters, contain only lowercase letters, digits, hyphens, underscores, and forward slashes, and start with a letter or digit."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
