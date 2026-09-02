# Private Cloud Map DNS namespace backing ECS Service Connect — this is the
# ECS/Fargate equivalent of Kubernetes' in-cluster Service DNS
# (<service>.<namespace>.svc.cluster.local), letting nginx/app/worker/probe/
# runner reach each other (and Redis/ClickHouse) by short name
# (e.g. http://app:3002) instead of hardcoded IPs.
resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = var.namespace
  description = "Service Connect namespace for ${var.name}"
  vpc         = var.vpc_id
  tags        = var.tags
}
