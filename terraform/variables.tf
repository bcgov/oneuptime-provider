variable "aws_region" {
  description = "AWS region to deploy the EKS cluster into. Platform constraint: only ca-central-1 (Canada Central) is supported."
  type        = string
  default     = "ca-central-1"

  validation {
    condition     = var.aws_region == "ca-central-1"
    error_message = "Only the ca-central-1 region is supported on this platform."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster (and the prefix used for related resources)."
  type        = string
  default     = "oneuptime"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.30"
}

# --- Platform-managed networking --------------------------------------------
# VPCs and subnets are provisioned and owned by the platform team and cannot
# be created or modified by users (no `aws_vpc`/`aws_subnet` resources, and no
# tagging of them either). Rather than requiring subnet/VPC IDs to be copied
# in by hand, they're looked up by their `Name` tag in data.tf — set these
# variables to match your environment's Name tags.

variable "vpc_name" {
  type        = string
  description = "Value of the Name tag for the platform-managed VPC to deploy the EKS cluster into."
  default     = "Dev"
}

variable "subnet_a" {
  type        = string
  description = "Value of the Name tag for the app subnet in AZ a. This platform only provisions one subnet tier, used for both the EKS cluster and the Network Load Balancer exposing OneUptime."
  default     = "Dev-App-A"
}

variable "subnet_b" {
  type        = string
  description = "Value of the Name tag for the app subnet in AZ b. This platform only provisions one subnet tier, used for both the EKS cluster and the Network Load Balancer exposing OneUptime."
  default     = "Dev-App-B"
}

variable "node_instance_types" {
  description = "Instance types for the default managed node group. OneUptime runs Postgres, Redis, ClickHouse and several app pods, so pick something with enough memory (>= 4 vCPU / 16 GiB per node is a reasonable starting point)."
  type        = list(string)
  default     = ["m6i.xlarge"]
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "node_group_desired_size" {
  description = "Desired number of worker nodes at creation time."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Common tags applied to every AWS resource this repo creates or uses (via provider default_tags, the gp3 StorageClass's EBS tagSpecification, and the nginx Service's LoadBalancer annotation), so all of OneUptime's AWS spend rolls up under one consistent set of tags for cost allocation/expense tracking."
  type        = map(string)
  default = {
    Project      = "oneuptime"
    ManagedBy    = "terraform"
    CostTracking = "oneuptime"
  }
}
