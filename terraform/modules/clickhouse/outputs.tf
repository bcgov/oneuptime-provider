output "security_group_id" {
  value = aws_security_group.this.id
}

output "native_dns_name" {
  value = "clickhouse"
}

output "http_dns_name" {
  value = "clickhouse-http"
}
