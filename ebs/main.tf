
# main.tf

locals {
  snapshot_enabled = try(var.ebs_config.snapshot_config.enabled, false)
  volume_name     = var.prefix != "" ? "${var.prefix}-${var.volume_name}" : var.volume_name
  
  cloudwatch_log_group_name = var.logging.mode != "disabled" ? (
    "/aws/ebs/${local.volume_name}"
  ) : null

  common_tags = merge(
    var.tags,
    {
      "managed-by" = "terraform"
      "module"     = "secure-ebs"
    }
  )
}

# KMS key creation if enabled
resource "aws_kms_key" "this" {
  count = var.kms_key.create ? 1 : 0

  description             = "KMS key for ${local.volume_name} EBS volume"
  deletion_window_in_days = var.kms_key.deletion_window_in_days
  enable_key_rotation     = var.kms_key.enable_key_rotation
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = concat(
            ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
            var.kms_key.key_administrators
          )
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ],
    var.kms_key.key_users != null ? [
      {
        Sid    = "Allow Key Users"
        Effect = "Allow"
        Principal = {
          AWS = var.kms_key.key_users
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ec2.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ] : [])
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "this" {
  count = var.kms_key.create ? 1 : 0

  name          = "alias/${local.volume_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

# CloudWatch Log Group for EBS operations logging
resource "aws_cloudwatch_log_group" "this" {
  count = var.logging.mode != "disabled" ? 1 : 0

  name              = local.cloudwatch_log_group_name
  retention_in_days = var.logging.retention_days
  kms_key_id       = var.kms_key.create ? aws_kms_key.this[0].arn : var.kms_key.key_arn

  tags = local.common_tags
}

# CloudTrail for EBS API logging (stores logs in S3 bucket)
resource "aws_cloudtrail" "ebs_operations" {
  count = var.logging.mode != "disabled" ? 1 : 0

  name           = "${local.volume_name}-cloudtrail"
  s3_bucket_name = var.logging.cloudtrail_bucket_name
  s3_key_prefix  = "ebs-logs/${local.volume_name}/"

  include_global_service_events = false
  is_multi_region_trail        = false
  enable_logging               = true

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    data_resource {
      type   = "AWS::EBS::Volume"
      values = [aws_ebs_volume.main.arn]
    }
    data_resource {
      type   = "AWS::EBS::Snapshot"
      values = ["${aws_ebs_volume.main.arn}/*"]
    }
  }

  tags = local.common_tags
}

# Main EBS volume with encryption
resource "aws_ebs_volume" "main" {
  availability_zone = var.ebs_config.availability_zone
  size              = var.ebs_config.size
  type              = var.ebs_config.volume_type
  iops              = var.ebs_config.volume_type == "gp3" || var.ebs_config.volume_type == "io1" || var.ebs_config.volume_type == "io2" ? var.ebs_config.iops : null
  throughput        = var.ebs_config.volume_type == "gp3" ? var.ebs_config.throughput : null
  
  encrypted  = true
  kms_key_id = var.kms_key.create ? aws_kms_key.this[0].arn : var.kms_key.key_arn

  final_snapshot = var.ebs_config.final_snapshot
  
  tags = merge(local.common_tags, {
    Name = local.volume_name
    Type = "secure-ebs-volume"
  })
}

# EBS Volume Access Control Policy (prevents unauthorized access)
resource "aws_iam_policy" "ebs_volume_access" {
  count = var.ebs_config.create_access_policy ? 1 : 0
  
  name        = "${local.volume_name}-access-policy"
  description = "IAM policy for secure access to ${local.volume_name} EBS volume"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyUnencryptedVolumeOperations"
        Effect = "Deny"
        Action = [
          "ec2:AttachVolume",
          "ec2:CreateVolume",
          "ec2:ModifyVolume"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "ec2:Encrypted" = "false"
          }
        }
      },
      {
        Sid    = "AllowVolumeOperationsWithEncryption"
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumeStatus",
          "ec2:ModifyVolume"
        ]
        Resource = [
          aws_ebs_volume.main.arn,
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        ]
        Condition = {
          StringEquals = {
            "ec2:VolumeTag/Name" = local.volume_name
          }
        }
      },
      {
        Sid    = "AllowSnapshotOperations"
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:DescribeSnapshots",
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:VolumeTag/Name" = local.volume_name
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# EBS Snapshot (provides versioning-like data protection)
resource "aws_ebs_snapshot" "initial" {
  count = var.ebs_config.create_initial_snapshot ? 1 : 0
  
  volume_id   = aws_ebs_volume.main.id
  description = "Initial snapshot of ${local.volume_name}"
  
  tags = merge(local.common_tags, {
    Name = "${local.volume_name}-initial-snapshot"
    Type = "initial-backup"
  })
}

# Data Lifecycle Manager policy for automated snapshots (provides lifecycle management)
resource "aws_dlm_lifecycle_policy" "ebs_snapshots" {
  count = var.ebs_config.snapshot_policy_enabled ? 1 : 0
  
  description        = "EBS snapshot lifecycle policy for ${local.volume_name}"
  execution_role_arn = aws_iam_role.dlm_lifecycle[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types   = ["VOLUME"]
    target_tags = {
      Name = local.volume_name
    }

    schedule {
      name = "Daily snapshots"
      
      create_rule {
        interval      = var.ebs_config.snapshot_schedule.interval
        interval_unit = var.ebs_config.snapshot_schedule.interval_unit
        times         = var.ebs_config.snapshot_schedule.times
      }

      retain_rule {
        count = var.ebs_config.snapshot_schedule.retain_count
      }

      tags_to_add = merge(local.common_tags, {
        SnapshotCreator = "DLM"
        VolumeId        = aws_ebs_volume.main.id
      })

      copy_tags = true
    }
  }

  tags = local.common_tags
}

# IAM role for DLM lifecycle policy
resource "aws_iam_role" "dlm_lifecycle" {
  count = var.ebs_config.snapshot_policy_enabled ? 1 : 0

  name = "${local.volume_name}-dlm-lifecycle-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for DLM lifecycle policy
resource "aws_iam_role_policy" "dlm_lifecycle" {
  count = var.ebs_config.snapshot_policy_enabled ? 1 : 0

  name = "${local.volume_name}-dlm-lifecycle-policy"
  role = aws_iam_role.dlm_lifecycle[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:DeleteSnapshot",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:ModifySnapshotAttribute"
        ]
        Resource = "*"
      }
    ]
  })
}

