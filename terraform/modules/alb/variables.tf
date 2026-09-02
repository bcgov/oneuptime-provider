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
