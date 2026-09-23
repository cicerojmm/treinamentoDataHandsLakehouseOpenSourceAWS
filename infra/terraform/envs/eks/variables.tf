variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
  default     = "data-platform-eks"
}

variable "cluster_version" {
  description = "Versão do Kubernetes"
  type        = string
  default     = "1.32"
}

variable "node_instance_type" {
  description = "Tipo de instância dos nodes"
  type        = string
  default     = "t3.large"
}

variable "node_desired_size" {
  description = "Número desejado de nodes"
  type        = number
  default     = 4
}

variable "tags" {
  description = "Tags para todos os recursos"
  type        = map(string)
  default = {
    Project     = "data-platform"
    Environment = "eks"
    ManagedBy   = "terraform"
  }
}
