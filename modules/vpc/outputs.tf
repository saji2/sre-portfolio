#------------------------------------------------------------------------------
# VPC Module Outputs
#------------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_eks_subnet_ids" {
  description = "IDs of the private EKS subnets"
  value       = aws_subnet.private_eks[*].id
}

output "private_data_subnet_ids" {
  description = "IDs of the private data subnets"
  value       = aws_subnet.private_data[*].id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "availability_zones" {
  description = "List of availability zones used"
  value       = local.azs
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_eks_route_table_ids" {
  description = "IDs of the private EKS route tables"
  value       = aws_route_table.private_eks[*].id
}

output "private_data_route_table_id" {
  description = "ID of the private data route table"
  value       = aws_route_table.private_data.id
}
