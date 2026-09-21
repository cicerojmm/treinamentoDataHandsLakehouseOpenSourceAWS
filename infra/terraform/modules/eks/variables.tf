variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "cluster_version" {
  description = "Versão do Kubernetes"
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas para os nodes"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "IDs das subnets públicas"
  type        = list(string)
}

variable "node_instance_type" {
  description = "Tipo de instância dos nodes"
  type        = string
  default     = "t3.large"
}

variable "node_desired_size" {
  description = "Número desejado de nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Número mínimo de nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Número máximo de nodes"
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Tamanho do disco dos nodes (GB)"
  type        = number
  default     = 50
}

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}
