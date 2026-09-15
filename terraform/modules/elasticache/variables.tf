variable "name" {
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

variable "node_type" {
  type = string
}

variable "auth_token" {
  description = "Redis AUTH token (min 16 chars) — required because transit_encryption_enabled is true."
  type        = string
  sensitive   = true
}

variable "tags" {
  type = map(string)
}
