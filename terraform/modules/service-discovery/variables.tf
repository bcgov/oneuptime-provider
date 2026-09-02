variable "name" {
  type = string
}

variable "namespace" {
  description = "Private DNS namespace name, e.g. 'oneuptime.local'."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "tags" {
  type = map(string)
}
