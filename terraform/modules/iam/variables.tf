variable "name" {
  type = string
}

variable "secret_arn" {
  description = "ARN of the Secrets Manager secret every task execution role needs read access to, to resolve `secrets` blocks in its task definition."
  type        = string
}

variable "service_names" {
  description = "Set of service names to create a dedicated (initially empty) task IAM role for."
  type        = set(string)
}

variable "tags" {
  type = map(string)
}
