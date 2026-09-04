terraform {
  required_version = ">= 1.5.0"

  # Remote state, backed by S3 with native S3 locking (Terraform >= 1.10).
  # This is deliberately NOT commented-out/optional: local-only state is
  # what caused repeated "AlreadyExists" cascades during this project's
  # troubleshooting — every time local state was lost or reset, Terraform
  # forgot about real AWS resources it had already created (which don't
  # disappear just because the state file did), and the next `apply` tried
  # to recreate everything from scratch. You (the person running this) must
  # create the S3 bucket yourself first (see docs/deploy-aws.md, "Remote
  # state setup") — bucket names are globally unique so `bucket` below is a
  # placeholder to replace with your own.
  backend "s3" {
    bucket       = "one-uptime-state"
    key          = "oneuptime/terraform.tfstate"
    region       = "ca-central-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
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
