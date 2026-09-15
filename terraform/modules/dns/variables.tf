variable "public_hostname" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "alb_dns_name" {
  type = string
}

variable "alb_zone_id" {
  type = string
}

variable "tags" {
  type = map(string)
}
