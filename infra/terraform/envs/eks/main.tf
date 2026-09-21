module "vpc" {
  source = "../../modules/vpc"

  cluster_name = var.cluster_name
  tags         = var.tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  tags               = var.tags
}

module "iam_irsa" {
  source = "../../modules/iam-irsa"

  cluster_name      = var.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  tags              = var.tags

  depends_on = [module.eks]
}

resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }

  depends_on = [module.iam_irsa]
}
