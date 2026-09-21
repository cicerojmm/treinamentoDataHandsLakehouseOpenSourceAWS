aws_region         = "us-east-2"
cluster_name       = "data-platform-eks"
cluster_version    = "1.32"
node_instance_type = "t3.large"
node_desired_size  = 3

tags = {
  Project     = "data-platform"
  Environment = "eks"
  ManagedBy   = "terraform"
}
