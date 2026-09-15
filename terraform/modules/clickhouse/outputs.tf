output "security_group_id" {
  value = aws_security_group.this.id
}

output "native_dns_name" {
  value = "clickhouse"
}

output "http_dns_name" {
  value = "clickhouse-http"
}

output "native_discovery_dns_name" {
  value = "${aws_service_discovery_service.native.name}.${var.namespace_name}"
}
