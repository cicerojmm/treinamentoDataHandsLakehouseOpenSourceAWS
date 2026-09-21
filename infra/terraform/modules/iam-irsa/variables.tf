variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do OIDC provider do EKS"
  type        = string
}

variable "oidc_issuer_url" {
  description = "URL do OIDC issuer (sem https://)"
  type        = string
}

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}
