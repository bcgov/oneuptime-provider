output "security_group_id" {
  value = aws_security_group.this.id
}

output "native_dns_name" {
  value = "clickhouse"
}

output "http_dns_name" {
  value = "clickhouse-http"
}

# Real Route 53 private-hosted-zone DNS name (classic Cloud Map service
# discovery), resolvable from ANY task in the VPC — including standalone
# `run-task` invocations (e.g. the `migrate` task) that aren't Service
# Connect clients and therefore can't resolve the "clickhouse" alias above.
output "native_discovery_dns_name" {
  value = "${aws_service_discovery_service.native.name}.${var.namespace_name}"
}
