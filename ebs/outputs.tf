# outputs.tf

output "volume_id" {
  description = "The ID of the EBS volume"
  value       = aws_ebs_volume.main.id
}

output "volume_arn" {
  description = "The ARN of the EBS volume"
  value       = aws_ebs_volume.main.arn
}

output "volume_size" {
  description = "The size of the EBS volume in GB"
  value       = aws_ebs_volume.main.size
}

output "volume_type" {
  description = "The type of the EBS volume"
  value       = aws_ebs_volume.main.type
}

output "volume_encrypted" {
  description = "Whether the EBS volume is encrypted"
  value       = aws_ebs_volume.main.encrypted
}

output "kms_key_arn" {
  description = "The ARN of the KMS key used for encryption"
  value       = var.kms_key.create ? aws_kms_key.this[0].arn : var.kms_key.key_arn
}

output "kms_key_id" {
  description = "The ID of the KMS key used for encryption"
  value       = var.kms_key.create ? aws_kms_key.this[0].id : null
}

output "kms_alias_name" {
  description = "The alias name of the KMS key"
  value       = var.kms_key.create ? aws_kms_alias.this[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "The ARN of the CloudWatch log group for EBS operations"
  value       = var.logging.mode != "disabled" ? aws_cloudwatch_log_group.this[0].arn : null
}

output "cloudtrail_arn" {
  description = "The ARN of the CloudTrail for EBS operations logging"
  value       = var.logging.mode != "disabled" ? aws_cloudtrail.ebs_operations[0].arn : null
}

output "access_policy_arn" {
  description = "The ARN of the IAM policy for EBS volume access control"
  value       = var.ebs_config.create_access_policy ? aws_iam_policy.ebs_volume_access[0].arn : null
}

output "availability_zone" {
  description = "The availability zone where the EBS volume is created"
  value       = aws_ebs_volume.main.availability_zone
}
