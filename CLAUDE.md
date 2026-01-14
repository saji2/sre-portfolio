# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Terraform infrastructure-as-code project for an SRE portfolio demonstrating AWS EKS, Kubernetes, and cloud infrastructure skills. The project provisions a complete AWS environment for a task management web application with comprehensive monitoring and chaos engineering capabilities.

## Common Commands

```bash
# Initialize Terraform
terraform init

# Format Terraform files
terraform fmt -recursive

# Validate configuration
terraform validate

# Preview changes
terraform plan

# Apply infrastructure changes
terraform apply

# Destroy infrastructure
terraform destroy

# Configure kubectl after EKS deployment
aws eks update-kubeconfig --name sre-portfolio-cluster --region ap-northeast-1
```

## Architecture

### Target Infrastructure
- **VPC**: Multi-AZ (3 AZs in ap-northeast-1) with public/private subnets
  - CIDR: `10.0.0.0/16`
  - Public subnets: ALB, NAT Gateways
  - Private subnets (EKS): Worker nodes
  - Private subnets (Data): RDS, ElastiCache
- **EKS**: Kubernetes 1.28+ cluster with t3.medium node group (2-6 nodes)
- **RDS**: PostgreSQL 15 Multi-AZ (db.t3.micro)
- **ElastiCache**: Redis 7.0 with replication
- **ALB**: Application Load Balancer via AWS Load Balancer Controller

### Terraform Module Structure (Planned)
```
terraform/
├── environments/
│   ├── dev/
│   └── prod/
├── modules/
│   ├── vpc/
│   ├── eks/
│   ├── rds/
│   ├── elasticache/
│   └── monitoring/
└── backend.tf
```

### Kubernetes Namespaces
- `app-production`: Application workloads
- `monitoring`: Prometheus, Grafana
- `chaos-engineering`: Chaos Mesh

## Key Providers and Versions

From `.terraform.lock.hcl`:
- AWS Provider: v5.100.0
- Kubernetes Provider: v2.38.0
- Helm Provider: v2.17.0

Uses modules from:
- `terraform-aws-modules/eks/aws`
- `terraform-aws-modules/vpc/aws`

## Project Context

This is a 28-day SRE portfolio project:
- **Days 1-3**: Infrastructure + application deployment
- **Days 4-28**: Operations exercises (monitoring, chaos engineering, performance tuning)

See `sre-portfolio-requirements.md` and `sre-portfolio-architecture.md` for detailed specifications.
