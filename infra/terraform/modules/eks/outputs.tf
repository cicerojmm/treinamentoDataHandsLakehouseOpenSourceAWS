output "cluster_id" {
  description = "ID do cluster EKS"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA data do cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "URL do OIDC issuer"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN do OIDC provider"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "node_role_arn" {
  description = "ARN da IAM role dos nodes"
  value       = aws_iam_role.node.arn
}
