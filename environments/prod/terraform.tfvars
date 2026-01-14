#------------------------------------------------------------------------------
# SRE Portfolio - Production Environment Configuration
#------------------------------------------------------------------------------

# General
aws_region   = "ap-northeast-1"
project_name = "sre-portfolio"
environment  = "prod"

# VPC
vpc_cidr             = "10.0.0.0/16"
enable_nat_gateway   = true
single_nat_gateway   = false # Multiple NAT Gateways for HA
enable_vpc_flow_logs = true

# EKS
cluster_version     = "1.28"
node_instance_types = ["t3.medium"]
node_capacity_type  = "ON_DEMAND"
node_disk_size      = 30
node_desired_size   = 3
node_min_size       = 3
node_max_size       = 10

# RDS
rds_engine_version        = "15"
rds_instance_class        = "db.t3.small"
rds_allocated_storage     = 50
rds_max_allocated_storage = 200
rds_database_name         = "taskmanager"
rds_multi_az              = true
rds_skip_final_snapshot   = false
rds_deletion_protection   = true
rds_performance_insights  = true

# Redis
redis_engine_version     = "7.0"
redis_node_type          = "cache.t3.small"
redis_num_cache_clusters = 3
redis_automatic_failover = true
redis_multi_az           = true

# Monitoring
# IMPORTANT: Set alert_email before production deployment to receive CloudWatch alarm notifications
alert_email              = "" # Required: Set your ops team email address (e.g., "ops@example.com")
log_retention_days       = 30
create_cloudwatch_alarms = true

# Helm Charts
install_aws_lb_controller  = true
install_cluster_autoscaler = true
install_metrics_server     = true
