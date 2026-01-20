#------------------------------------------------------------------------------
# SRE Portfolio - Development Environment
# Main Terraform configuration
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Uncomment to use S3 backend
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "sre-portfolio/dev/terraform.tfstate"
  #   region         = "ap-northeast-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

#------------------------------------------------------------------------------
# Provider Configuration
#------------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

#------------------------------------------------------------------------------
# Local Variables
#------------------------------------------------------------------------------
locals {
  cluster_name = "${var.project_name}-cluster"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

#------------------------------------------------------------------------------
# VPC Module
#------------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  cluster_name       = local.cluster_name
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway
  enable_flow_logs   = var.enable_vpc_flow_logs

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# EKS Module
#------------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_eks_subnet_ids

  endpoint_private_access   = true
  endpoint_public_access    = true
  enabled_cluster_log_types = var.eks_cluster_log_types

  node_instance_types = var.node_instance_types
  capacity_type       = var.node_capacity_type
  node_disk_size      = var.node_disk_size
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  enable_aws_lb_controller  = true
  enable_cluster_autoscaler = true

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# RDS Module
#------------------------------------------------------------------------------
module "rds" {
  source = "../../modules/rds"

  project_name              = var.project_name
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.private_data_subnet_ids
  allowed_security_group_id = module.eks.cluster_primary_security_group_id

  engine_version        = var.rds_engine_version
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  database_name         = var.rds_database_name
  multi_az              = var.rds_multi_az
  skip_final_snapshot   = var.rds_skip_final_snapshot
  deletion_protection   = var.rds_deletion_protection

  create_cloudwatch_alarms = var.create_cloudwatch_alarms
  alarm_actions            = var.create_cloudwatch_alarms ? [module.monitoring.sns_topic_arn] : []

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# ElastiCache Module
#------------------------------------------------------------------------------
module "elasticache" {
  source = "../../modules/elasticache"

  project_name              = var.project_name
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.private_data_subnet_ids
  allowed_security_group_id = module.eks.cluster_primary_security_group_id

  engine_version             = var.redis_engine_version
  node_type                  = var.redis_node_type
  num_cache_clusters         = var.redis_num_cache_clusters
  automatic_failover_enabled = var.redis_automatic_failover
  multi_az_enabled           = var.redis_multi_az

  create_cloudwatch_alarms = var.create_cloudwatch_alarms
  alarm_actions            = var.create_cloudwatch_alarms ? [module.monitoring.sns_topic_arn] : []

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Monitoring Module
#------------------------------------------------------------------------------
module "monitoring" {
  source = "../../modules/monitoring"

  project_name = var.project_name
  aws_region   = var.aws_region
  cluster_name = local.cluster_name
  alert_email  = var.alert_email

  log_retention_days      = var.log_retention_days
  rds_instance_identifier = module.rds.db_instance_identifier
  elasticache_cluster_id  = "${var.project_name}-redis-001"

  create_fluent_bit_role = true
  oidc_provider_arn      = module.eks.oidc_provider_arn
  oidc_provider_url      = module.eks.oidc_provider_url

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# AWS Load Balancer Controller (Helm)
#------------------------------------------------------------------------------
resource "helm_release" "aws_load_balancer_controller" {
  count = var.install_aws_lb_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.aws_lb_controller_version

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.aws_lb_controller_role_arn
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  depends_on = [module.eks]
}

#------------------------------------------------------------------------------
# Cluster Autoscaler (Helm)
#------------------------------------------------------------------------------
resource "helm_release" "cluster_autoscaler" {
  count = var.install_cluster_autoscaler ? 1 : 0

  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = var.cluster_autoscaler_version

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.cluster_autoscaler_role_arn
  }

  depends_on = [module.eks]
}

#------------------------------------------------------------------------------
# Metrics Server (Helm)
#------------------------------------------------------------------------------
resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = var.metrics_server_version

  depends_on = [module.eks]
}

#------------------------------------------------------------------------------
# ECR Module
#------------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
  tags         = local.common_tags
}
