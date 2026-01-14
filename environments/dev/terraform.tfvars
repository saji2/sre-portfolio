#------------------------------------------------------------------------------
# SRE Portfolio - Development Environment Configuration
#------------------------------------------------------------------------------

# General
aws_region   = "ap-northeast-1"
project_name = "sre-portfolio"
environment  = "dev"

# VPC
vpc_cidr             = "10.0.0.0/16"
enable_nat_gateway   = true
single_nat_gateway   = true # Cost optimization: use single NAT Gateway
enable_vpc_flow_logs = false

# EKS
cluster_version     = "1.32"
node_instance_types = ["t3.medium"]
node_capacity_type  = "ON_DEMAND"
node_disk_size      = 20
node_desired_size   = 3
node_min_size       = 2
node_max_size       = 6

# RDS
rds_engine_version        = "15"
rds_instance_class        = "db.t3.micro"
rds_allocated_storage     = 20
rds_max_allocated_storage = 100
rds_database_name         = "taskmanager"
rds_multi_az              = false # Cost optimization: disable Multi-AZ for dev
rds_skip_final_snapshot   = true
rds_deletion_protection   = false

# Redis
redis_engine_version     = "7.0"
redis_node_type          = "cache.t3.micro"
redis_num_cache_clusters = 1     # Single node for cost optimization in dev
redis_automatic_failover = false # Requires Multi-AZ and multiple nodes
redis_multi_az           = false # Cost optimization: disable Multi-AZ for dev

# Monitoring
alert_email              = "" # Set your email address here
log_retention_days       = 7
create_cloudwatch_alarms = true

# Helm Charts
install_aws_lb_controller  = true
install_cluster_autoscaler = true
install_metrics_server     = true
