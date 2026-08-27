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

# Used by coredns.tf to patch the CoreDNS ConfigMap (see that file for why).
# Authenticates against the cluster this same apply just created/updated,
# via a short-lived exec-based token (avoids storing/refreshing a static
# token in state).
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}
