output "ebs_csi_driver_role_arn" {
  description = "ARN da role do EBS CSI Driver"
  value       = aws_iam_role.ebs_csi_driver.arn
}
