variable "name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "namespace_arn" {
  description = "ARN of the Cloud Map private DNS namespace (Service Connect) every service joins."
  type        = string
}

variable "image" {
  type = string
}

variable "cpu" {
  type = number
}

variable "memory" {
  type = number
}

variable "desired_count" {
  type = number
}

variable "container_port" {
  description = "Port the container listens on. Null for services that take no inbound traffic and aren't reached by siblings by name (rare — most OneUptime services expose at least a health-check HTTP port)."
  type        = number
  default     = null
}

variable "environment" {
  description = "List of {name, value} environment variables (plaintext — non-secret config only)."
  type        = list(object({ name = string, value = string }))
  default     = []
}

variable "secrets" {
  description = "List of {name, valueFrom} secrets resolved from Secrets Manager at task start."
  type        = list(object({ name = string, valueFrom = string }))
  default     = []
}

variable "task_execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "target_group_arn" {
  description = "ALB target group to register this service with. Only set for nginx — every other service is reached internally via Service Connect, never directly by the ALB."
  type        = string
  default     = null
}

variable "log_group_name" {
  type = string
}

variable "tags" {
  type = map(string)
}
