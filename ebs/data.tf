# data.tf
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get available availability zones for EBS volume placement
data "aws_availability_zones" "available" {
  state = "available"
}

# Get the default VPC for security group creation
data "aws_vpc" "default" {
  default = true
}

# Get latest Amazon Linux 2 AMI for example instance
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}