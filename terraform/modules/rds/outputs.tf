output "endpoint" {
  value = module.db.cluster_endpoint
}

output "port" {
  value = module.db.cluster_port
}

output "database_name" {
  value = var.database_name
}
