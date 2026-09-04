output "namespace_id" {
  value = aws_service_discovery_private_dns_namespace.this.id
}

output "namespace_name" {
  value = aws_service_discovery_private_dns_namespace.this.name
}

# ECS's `service_connect_configuration.namespace` argument requires the
# namespace's ARN or name — the bare ID (e.g. "ns-xxxx", from namespace_id
# above) is neither and will always fail with NamespaceNotFoundException,
# regardless of how long you wait after creation. Use this output for
# anything wiring up Service Connect.
output "namespace_arn" {
  value = aws_service_discovery_private_dns_namespace.this.arn
}
