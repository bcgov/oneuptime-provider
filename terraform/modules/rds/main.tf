# Amazon Aurora PostgreSQL (Serverless v2) — replaces the self-hosted
# PVC-backed Postgres StatefulSet from the EKS/Helm setup, since Fargate has
# no persistent block storage. Mirrors bcgov/otp-provider's terraform/
# modules/rds pattern.
resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "Aurora SG for ${var.name}: ingress only from OneUptime ECS task security groups."
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from OneUptime ECS tasks"
    from_port       = 5432
    to_port         = 5432
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

module "db" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 9.0"

  name           = var.name
  engine         = "aurora-postgresql"
  engine_mode    = "provisioned"
  engine_version = "15.15"

  vpc_id                 = var.vpc_id
  subnets                = var.subnet_ids
  create_db_subnet_group = true
  db_subnet_group_name   = var.name

  vpc_security_group_ids = [aws_security_group.this.id]

  storage_encrypted    = true
  apply_immediately    = true
  skip_final_snapshot  = true
  enable_http_endpoint = true

  serverlessv2_scaling_configuration = {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  instance_class = "db.serverless"
  instances = {
    one = {
      auto_minor_version_upgrade = false
    }
  }

  manage_master_user_password = false
  master_username             = "postgres"
  master_password             = var.db_password
  database_name               = var.database_name

  tags = var.tags
}
