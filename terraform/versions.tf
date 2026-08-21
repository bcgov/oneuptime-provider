terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Applied to every AWS resource this provider creates (VPC, subnets, NAT
  # gateway/EIP, EKS cluster/node groups, IAM roles, ...), on top of any
  # resource-specific `tags`. Keeps expense tracking/cost allocation reports
  # consistent without having to tag each resource block individually.
  default_tags {
    tags = var.tags
  }
}
