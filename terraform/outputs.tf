output "vpc_id" {
  description = "VPC ID housing the ECS cluster (platform-managed, looked up by var.vpc_name)."
  value       = data.aws_vpc.selected.id
}

output "subnet_ids" {
  description = "IDs of the two platform-managed subnets (looked up by var.subnet_a/var.subnet_b)."
  value       = [data.aws_subnet.a.id, data.aws_subnet.b.id]
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "alb_dns_name" {
  description = "Internal ALB's raw DNS name — only reachable from within the VPC. Browse to var.oneuptime_public_host instead once LZA's perimeter automation picks up the Public=True/PublicHost tags."
  value       = module.alb.alb_dns_name
}

output "secrets_manager_secret_arn" {
  description = "Secrets Manager secret holding ONEUPTIME_SECRET/ENCRYPTION_SECRET/DATABASE_PASSWORD/REDIS_AUTH_TOKEN/CLICKHOUSE_PASSWORD."
  value       = aws_secretsmanager_secret.this.arn
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "redis_endpoint" {
  value = module.elasticache.primary_endpoint_address
}

output "migrate_task_definition_arn" {
  description = "One-off DB migration task definition — run once via `aws ecs run-task` (see comment above aws_ecs_task_definition.migrate in main.tf) before relying on app/worker being healthy."
  value       = aws_ecs_task_definition.migrate.arn
}

output "ecs_task_security_group_id" {
  description = "Security group to pass as --network-configuration's securityGroups when running the migrate task manually."
  value       = aws_security_group.ecs_tasks.id
}

output "alb_access_logs_bucket" {
  description = "S3 bucket receiving ALB access logs, or null when var.enable_alb_access_logs is false (the default). Enable to debug whether requests actually reach nginx (e.g. diagnosing 504s) — every line shows the target's response code and processing time, or a timeout/-1 reason code if the ALB gave up waiting on nginx."
  value       = module.alb.alb_access_logs_bucket
}
