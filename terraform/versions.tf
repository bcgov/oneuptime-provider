terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Applied to every AWS resource this provider creates (ECS, RDS,
  # ElastiCache, EFS, ALB, IAM roles, Secrets Manager, ...), on top of any
  # resource-specific `tags`. Keeps expense tracking/cost allocation reports
  # consistent without having to tag each resource block individually.
  default_tags {
    tags = var.tags
  }
}
