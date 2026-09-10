variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "acm_certificate_arn" {
  type = string
}

variable "public_host_label" {
  type = string
}

variable "nginx_container_port" {
  type = number
}

variable "nginx_security_group_id" {
  description = "Security group attached to the nginx ECS service's ENIs — the ALB's egress rule (and the nginx SG's own ingress rule, added in main.tf where that SG is created) scope traffic to just this ALB<->nginx path."
  type        = string
}

variable "tags" {
  type = map(string)
}

variable "aws_region" {
  description = "AWS region, needed to look up the regional ELB service account for the access-log bucket policy on partitions that still require it (harmless/no-op on newer regions that only need the service-principal statement)."
  type        = string
}

variable "enable_access_logs" {
  description = "Enable ALB access logging to S3 (bucket created by this module). Turn on for debugging request flow (e.g. diagnosing 504s) - shows every request the ALB actually forwarded to a target, and its response code/latency, even when the target itself logs nothing."
  type        = bool
  default     = false
}
