terraform {
  backend "s3" {
    bucket       = "cjmm-datahandson-configs"
    key          = "terraform/lakehouse_opensource_eks/eks/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
