variable "ebs_config" {
  description = <<-EOT
    Configuration for the EBS volume behavior and security features.
    
    availability_zone        - (Required) The AZ where the volume will be created
    size                    - (Required) Size of the volume in GB
    volume_type             - (Optional) Type of EBS volume. Default: "gp3"
    iops                    - (Optional) IOPS for volume (required for io1/io2/gp3)
    throughput              - (Optional) Throughput for gp3 volumes (125-1000 MiB/s)
    final_snapshot          - (Optional) Create snapshot before deletion. Default: true
    create_access_policy    - (Optional) Create IAM access control policy. Default: true
    create_initial_snapshot - (Optional) Create initial snapshot after creation. Default: true
    snapshot_policy_enabled - (Optional) Enable DLM snapshot lifecycle policy. Default: true
    
    snapshot_schedule       - (Optional) Snapshot scheduling configuration:
      interval            - Schedule interval (1, 2, 3, 4, 6, 8, 12, 24)
      interval_unit       - Unit for interval ("HOURS")
      times               - List of times to create snapshots (24-hour format)
      retain_count        - Number of snapshots to retain
    
    Example:
    ```hcl
    ebs_config = {
      availability_zone = "us-west-2a"
      size = 100
      volume_type = "gp3"
      iops = 3000
      throughput = 250
      final_snapshot = true
      create_access_policy = true
      create_initial_snapshot = true
      snapshot_policy_enabled = true
      
      snapshot_schedule = {
        interval = 24
        interval_unit = "HOURS"
        times = ["03:00"]
        retain_count = 7
      }
    }
    ```
  EOT
  
  type = object({
    availability_zone        = string
    size                    = number
    volume_type             = optional(string, "gp3")
    iops                    = optional(number)
    throughput              = optional(number)
    final_snapshot          = optional(bool, true)
    create_access_policy    = optional(bool, true)
    create_initial_snapshot = optional(bool, true)
    snapshot_policy_enabled = optional(bool, true)
    
    snapshot_schedule       = optional(object({
      interval            = optional(number, 24)
      interval_unit       = optional(string, "HOURS")
      times               = optional(list(string), ["03:00"])
      retain_count        = optional(number, 7)
    }), {})
  })

  validation {
    condition     = var.ebs_config.size >= 1 && var.ebs_config.size <= 65536
    error_message = "EBS volume size must be between 1 and 65536 GB"
  }

  validation {
    condition = contains([
      "gp2", "gp3", "io1", "io2", "st1", "sc1"
    ], var.ebs_config.volume_type)
    error_message = "Invalid EBS volume type. Must be one of: gp2, gp3, io1, io2, st1, sc1"
  }

  validation {
    condition = (
      var.ebs_config.volume_type != "gp3" || 
      var.ebs_config.throughput == null || 
      (var.ebs_config.throughput >= 125 && var.ebs_config.throughput <= 1000)
    )
    error_message = "gp3 throughput must be between 125 and 1000 MiB/s"
  }

  validation {
    condition = (
      !contains(["io1", "io2", "gp3"], var.ebs_config.volume_type) ||
      var.ebs_config.iops != null
    )
    error_message = "IOPS must be specified for io1, io2, and gp3 volume types"
  }
}

# variables.tf

variable "prefix" {
  description = "Prefix to be used for all created resources. Should be RFC 1123 compliant."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.prefix)) || var.prefix == ""
    error_message = "Prefix must be RFC 1123 compliant: contain only lowercase alphanumeric characters or '-', start with alphanumeric, end with alphanumeric."
  }
}

variable "tags" {
  description = "A map of tags to be applied to all resources. Must include required tags per security standards."
  type        = map(string)
  default     = {}

  validation {
    condition     = contains(keys(var.tags), "Environment") && contains(keys(var.tags), "Owner")
    error_message = "Tags must include 'Environment' and 'Owner' as required by security standards."
  }
}

variable "volume_name" {
  description = "Name of the EBS volume. Must comply with AWS naming rules and not exceed 63 characters including prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]*[a-zA-Z0-9]$", var.volume_name))
    error_message = "Volume name must comply with AWS naming rules: alphanumeric characters, dots, underscores, and hyphens."
  }
}

# Example of a complex variable with comprehensive documentation
variable "kms_key" {
  description = <<-EOT
    Configuration for KMS key. Either create a new key or use an existing one.
    
    create        - Whether to create a new KMS key
    key_arn      - ARN of existing KMS key if create is false
    deletion_window_in_days - Duration in days before key is deleted (7-30 days)
    enable_key_rotation    - Whether to enable automatic key rotation
    key_administrators    - List of IAM ARNs that can administer the key
    key_users            - List of IAM ARNs that can use the key
    
    Example:
    ```hcl
    kms_key = {
      create = true
      deletion_window_in_days = 7
      enable_key_rotation = true
      key_administrators = ["arn:aws:iam::123456789012:user/admin"]
      key_users = ["arn:aws:iam::123456789012:role/app-role"]
    }
    ```
  EOT
  type = object({
    create                  = bool
    key_arn                = optional(string)
    deletion_window_in_days = optional(number, 7)
    enable_key_rotation    = optional(bool, true)
    key_administrators    = optional(list(string), [])
    key_users            = optional(list(string), [])
  })

  validation {
    condition     = (var.kms_key.deletion_window_in_days >= 7 && var.kms_key.deletion_window_in_days <= 30) || var.kms_key.deletion_window_in_days == null
    error_message = "deletion_window_in_days must be between 7 and 30 days"
  }
}

variable "logging" {
  description = <<-EOT
    Configuration for EBS volume logging and monitoring.
    
    Mode can be one of:
    - "create_new"    : Creates new logging resources (CloudWatch, CloudTrail)
    - "use_existing"  : Uses existing logging resources
    - "disabled"      : Disables logging
    
    When mode = "use_existing":
    - cloudtrail_bucket_name is required for CloudTrail logs
    
    When mode = "create_new":
    - retention_days is optional (defaults to 90)
    - cloudtrail_bucket_name is required for CloudTrail storage
    
    Example (Create New):
    ```hcl
    logging = {
      mode = "create_new"
      retention_days = 90
      cloudtrail_bucket_name = "my-cloudtrail-bucket"
    }
    ```
    
    Example (Use Existing):
    ```hcl
    logging = {
      mode = "use_existing"
      cloudtrail_bucket_name = "existing-cloudtrail-bucket"
    }
    ```
  EOT
  
  type = object({
    mode = string
    # CloudTrail configuration
    cloudtrail_bucket_name = optional(string)
    # CloudWatch configuration
    retention_days = optional(number, 90)
  })

  validation {
    condition = contains(["create_new", "use_existing", "disabled"], var.logging.mode)
    error_message = "logging.mode must be one of: create_new, use_existing, disabled"
  }

  validation {
    condition = (
      var.logging.mode == "disabled" || 
      var.logging.cloudtrail_bucket_name != null
    )
    error_message = "When logging is enabled, cloudtrail_bucket_name is required"
  }
}
