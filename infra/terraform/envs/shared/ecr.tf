module "ecr" {
  source   = "../../modules/ecr"
  for_each = toset(local.ecr_repositories)

  repository_name = "${var.project_name}/${each.value}"
  tags            = local.common_tags
}

output "ecr_repository_urls" {
  description = "URLs of all ECR repositories"
  value       = { for k, v in module.ecr : k => v.repository_url }
}
