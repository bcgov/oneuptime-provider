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
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_ids" {
  type = list(string)
}

variable "task_execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "cpu" {
  type    = number
  default = 1024
}

variable "memory" {
  type    = number
  default = 2048
}

variable "username" {
  type    = string
  default = "oneuptime"
}

variable "database_name" {
  type    = string
  default = "oneuptime"
}

variable "password_secret_arn" {
  description = "Secrets Manager ARN (with :key:: JSON-key suffix) resolving to the ClickHouse password."
  type        = string
}

variable "tags" {
  type = map(string)
}
