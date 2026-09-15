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
  description = "Security groups (ECS task SGs) allowed to reach Postgres on 5432."
  type        = list(string)
}

variable "database_name" {
  type    = string
  default = "oneuptimedb"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "min_capacity" {
  type = number
}

variable "max_capacity" {
  type = number
}

variable "tags" {
  type = map(string)
}
