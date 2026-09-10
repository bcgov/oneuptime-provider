variable "name" {
  type = string
}

variable "secret_arns" {
  description = "ARNs of the Secrets Manager secrets every task execution role needs read access to, to resolve `secrets` blocks in its task definitions."
  type        = list(string)
}

variable "service_names" {
  description = "Set of service names to create a dedicated (initially empty) task IAM role for."
  type        = set(string)
}

variable "tags" {
  type = map(string)
}
