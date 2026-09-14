variable "aws_region" {
  description = "AWS region to deploy into. Platform constraint: only ca-central-1 (Canada Central) is supported."
  type        = string
  default     = "ca-central-1"

  validation {
    condition     = var.aws_region == "ca-central-1"
    error_message = "Only the ca-central-1 region is supported on this platform."
  }
}

variable "name" {
  description = "Name/prefix used for the ECS cluster and every resource this repo creates (security groups, IAM roles, RDS, ElastiCache, EFS, Cloud Map namespace, ...)."
  type        = string
  default     = "oneuptime"
}

# --- Platform-managed networking --------------------------------------------
# VPCs and subnets are provisioned and owned by the platform team and cannot
# be created or modified by users (no `aws_vpc`/`aws_subnet` resources, and no
# tagging of them either). They're looked up by their `Name` tag in data.tf —
# set these variables to match your environment's Name tags.

variable "vpc_name" {
  type        = string
  description = "Value of the Name tag for the platform-managed VPC to deploy into."
  default     = "Dev"
}

variable "subnet_a" {
  type        = string
  description = "Value of the Name tag for the app subnet in AZ a. This platform only provisions one subnet tier, used for the ECS tasks, the internal ALB, RDS, ElastiCache and EFS mount targets."
  default     = "Dev-App-A"
}

variable "subnet_b" {
  type        = string
  description = "Value of the Name tag for the app subnet in AZ b."
  default     = "Dev-App-B"
}

# --- Public exposure (LZA) ---------------------------------------------------

variable "acm_certificate_arn" {
  description = "ARN of the pre-existing ACM certificate the internal ALB's HTTPS listener terminates with. Not provisioned by this repo — obtain from your platform team/.env, same as the previous EKS setup."
  type        = string
}

variable "oneuptime_public_host" {
  type        = string
  description = "Public hostname OneUptime is browsed at (LZA's perimeter hostname, e.g. oneuptime.<account>.stratus.cloud.gov.bc.ca). Used both for the nginx PUBLIC_HOST env var and for the Route 53 private hosted zone record that lets OneUptime's self-referential SSR calls resolve this hostname without leaving the VPC (this platform's VPC has no Internet Gateway)."
  default     = "oneuptime.b46814-dev.stratus.cloud.gov.bc.ca"
}

variable "public_host_label" {
  description = "Label(s) for the ALB's PublicHost tag (space-separated, no dots) — see LZA's 'Making internal ALB publicly reachable using tags' doc. Must match the first label of oneuptime_public_host."
  type        = string
  default     = "oneuptime"
}

variable "enable_alb_access_logs" {
  description = "Enable ALB access logging to a Terraform-managed S3 bucket. Off by default; turn on temporarily to debug request-flow issues (e.g. 504s) — the access log shows every request the ALB actually forwarded to nginx and its response code/latency, even when nginx/app themselves log nothing for it."
  type        = bool
  default     = false
}

# --- ECS sizing (simplified/dev scope — bump before production) -------------

variable "service_sizing" {
  description = <<-EOT
    Per-service Fargate task sizing and desired count. Keys must match the
    services wired up in main.tf (nginx, app, home, worker, probe, runner,
    clickhouse). `container_port` is null for services that take no inbound
    traffic (worker, probe, runner) — see each upstream chart service's
    `<service>.ports.http` in the OneUptime Helm chart's values.yaml to
    confirm the exact port before deploying.
  EOT
  type = map(object({
    cpu            = number
    memory         = number
    desired_count  = number
    container_port = optional(number)
  }))
  default = {
    # nginx's default.conf.template listens on 7849 (not the commonly assumed
    # 8080) — confirmed against the actual running container; the ALB target
    # group/health check derive this same value via nginx_container_port in
    # main.tf, so this single change fixes both.
    nginx  = { cpu = 512, memory = 1024, desired_count = 1, container_port = 7849 }
    app    = { cpu = 1024, memory = 2048, desired_count = 1, container_port = 3002 }
    home   = { cpu = 512, memory = 1024, desired_count = 1, container_port = 3003 }
    worker = { cpu = 1024, memory = 2048, desired_count = 1, container_port = 3002 }
    probe  = { cpu = 512, memory = 1024, desired_count = 1, container_port = 3005 }
    runner = { cpu = 256, memory = 512, desired_count = 1, container_port = 3006 }
  }
}

variable "image_tag" {
  description = "OneUptime image tag to deploy across all services (e.g. 'release', or a pinned version — see https://github.com/OneUptime/oneuptime/releases). Pin this before production use."
  type        = string
  default     = "release"
}

# --- Databases ----------------------------------------------------------

variable "rds_min_capacity" {
  description = "Aurora PostgreSQL Serverless v2 minimum ACUs."
  type        = number
  default     = 0.5
}

variable "rds_max_capacity" {
  description = "Aurora PostgreSQL Serverless v2 maximum ACUs."
  type        = number
  default     = 2
}

variable "redis_node_type" {
  description = "ElastiCache node type for the single-node Redis replication group (dev/small scope — no cluster mode/HA)."
  type        = string
  default     = "cache.t4g.micro"
}

variable "clickhouse_image_tag" {
  description = "clickhouse/clickhouse-server image tag. Keep aligned with the version pinned in the OneUptime Helm chart's values.yaml (clickhouse.image.tag)."
  type        = string
  default     = "26.7"
}

variable "clickhouse_efs_size_gib" {
  description = "Informational only (EFS is elastic/pay-per-use, no fixed size) — sizing knob reserved for a future EFS provisioned-throughput setting."
  type        = number
  default     = 25
}

variable "tags" {
  description = "Common tags applied to every AWS resource this repo creates, so all of OneUptime's AWS spend rolls up under one consistent set of tags for cost allocation/expense tracking."
  type        = map(string)
  default = {
    Project      = "oneuptime"
    ManagedBy    = "terraform"
    CostTracking = "oneuptime"
  }
}
