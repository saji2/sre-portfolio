#------------------------------------------------------------------------------
# Terraform Backend Configuration
#
# This file provides a template for S3 backend configuration.
# To use the S3 backend, uncomment the backend block in your environment's
# main.tf file and create the required S3 bucket and DynamoDB table.
#------------------------------------------------------------------------------

# Example S3 bucket and DynamoDB table creation
# These resources should be created manually or in a separate Terraform
# configuration before using the S3 backend.

# resource "aws_s3_bucket" "terraform_state" {
#   bucket = "sre-portfolio-terraform-state"
#
#   lifecycle {
#     prevent_destroy = true
#   }
#
#   tags = {
#     Name        = "Terraform State Bucket"
#     Environment = "shared"
#     ManagedBy   = "terraform"
#   }
# }
#
# resource "aws_s3_bucket_versioning" "terraform_state" {
#   bucket = aws_s3_bucket.terraform_state.id
#
#   versioning_configuration {
#     status = "Enabled"
#   }
# }
#
# resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
#   bucket = aws_s3_bucket.terraform_state.id
#
#   rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm = "aws:kms"
#     }
#   }
# }
#
# resource "aws_s3_bucket_public_access_block" "terraform_state" {
#   bucket = aws_s3_bucket.terraform_state.id
#
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
# }
#
# resource "aws_dynamodb_table" "terraform_locks" {
#   name         = "terraform-state-lock"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "LockID"
#
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
#
#   tags = {
#     Name        = "Terraform Lock Table"
#     Environment = "shared"
#     ManagedBy   = "terraform"
#   }
# }
