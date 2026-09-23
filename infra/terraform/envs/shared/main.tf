terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "data-platform"
}

locals {
  common_tags = {
    Project     = var.project_name
    ManagedBy   = "terraform"
    Environment = "shared"
  }

  ecr_repositories = [
    "airflow-dags",
    "dbt-project",
    "api-service",
    "spark-jobs",
    "metabase",
  ]
}
