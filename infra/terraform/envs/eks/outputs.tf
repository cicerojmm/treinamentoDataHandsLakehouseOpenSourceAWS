output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA data do cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "vpc_id" {
  description = "ID da VPC"
  value       = module.vpc.vpc_id
}

output "nat_gateway_ip" {
  description = "IP público do NAT Gateway"
  value       = module.vpc.nat_gateway_ip
}

output "kubeconfig_command" {
  description = "Comando para configurar kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
