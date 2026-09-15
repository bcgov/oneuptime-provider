# Amazon ElastiCache for Redis — replaces the self-hosted Redis
# StatefulSet. Single node, no cluster mode/replication: matches this
# repo's dev/small scope (the EKS setup also ran Redis with persistence
# disabled by default).
resource "aws_security_group" "this" {
  name        = "${var.name}-redis"
  description = "Redis SG for ${var.name}: ingress only from OneUptime ECS task security groups."
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from OneUptime ECS tasks"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = "OneUptime Redis (${var.name})"

  engine         = "redis"
  engine_version = "7.1"
  node_type      = var.node_type

  num_cache_clusters = 1

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.auth_token

  apply_immediately = true

  tags = var.tags
}
