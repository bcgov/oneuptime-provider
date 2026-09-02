###############################################################################
# Shared ECS platform: cluster, service discovery
###############################################################################

module "service_discovery" {
  source = "./modules/service-discovery"

  name      = var.name
  namespace = "${var.name}.local"
  vpc_id    = data.aws_vpc.selected.id
  tags      = var.tags
}

module "ecs_cluster" {
  source = "./modules/ecs-cluster"

  name = var.name
  tags = var.tags
}

###############################################################################
# Networking: one shared security group for every ECS task (nginx included)
###############################################################################
# All OneUptime services talk to each other over Service Connect (east-west),
# so they share one security group with a self-referencing ingress rule
# (mirrors how pods in the same EKS cluster could reach each other by
# default). The ALB is only allowed to reach nginx's container port — see the
# aws_security_group_rule below, added after the alb module exists (kept
# out of the alb module itself to avoid a security-group creation cycle
# between the two modules).
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name}-ecs-tasks"
  description = "Shared security group for all OneUptime ECS Fargate tasks."
  vpc_id      = data.aws_vpc.selected.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_security_group_rule" "ecs_tasks_self_ingress" {
  type              = "ingress"
  security_group_id = aws_security_group.ecs_tasks.id
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  self              = true
  description       = "Service Connect east-west traffic between OneUptime services."
}

resource "aws_security_group_rule" "ecs_tasks_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ecs_tasks.id
  from_port                = var.service_sizing["nginx"].container_port
  to_port                  = var.service_sizing["nginx"].container_port
  protocol                 = "tcp"
  source_security_group_id = module.alb.alb_security_group_id
  description              = "ALB to nginx"
}

###############################################################################
# Public exposure: internal ALB (LZA Pattern B) + Route 53 self-reference fix
###############################################################################

module "alb" {
  source = "./modules/alb"

  name                    = var.name
  vpc_id                  = data.aws_vpc.selected.id
  vpc_cidr                = data.aws_vpc.selected.cidr_block
  subnet_ids              = [data.aws_subnet.a.id, data.aws_subnet.b.id]
  acm_certificate_arn     = var.acm_certificate_arn
  public_host_label       = var.public_host_label
  nginx_container_port    = var.service_sizing["nginx"].container_port
  nginx_security_group_id = aws_security_group.ecs_tasks.id
  tags                    = var.tags
}

module "dns" {
  source = "./modules/dns"

  public_hostname = var.oneuptime_public_host
  vpc_id          = data.aws_vpc.selected.id
  alb_dns_name    = module.alb.alb_dns_name
  alb_zone_id     = module.alb.alb_zone_id
  tags            = var.tags
}

###############################################################################
# Secrets
###############################################################################

resource "random_password" "oneuptime_secret" {
  length  = 64
  special = false
}

resource "random_password" "encryption_secret" {
  length  = 64
  special = false
}

resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "random_password" "redis_auth_token" {
  length  = 32
  special = false
}

resource "random_password" "clickhouse_password" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "this" {
  name = "${var.name}-secrets"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    ONEUPTIME_SECRET    = random_password.oneuptime_secret.result
    ENCRYPTION_SECRET   = random_password.encryption_secret.result
    DATABASE_PASSWORD   = random_password.db_password.result
    REDIS_AUTH_TOKEN    = random_password.redis_auth_token.result
    CLICKHOUSE_PASSWORD = random_password.clickhouse_password.result
  })
}

###############################################################################
# IAM
###############################################################################

module "iam" {
  source = "./modules/iam"

  name          = var.name
  secret_arn    = aws_secretsmanager_secret.this.arn
  service_names = setunion(toset(keys(var.service_sizing)), ["clickhouse"])
  tags          = var.tags
}

###############################################################################
# Data stores
###############################################################################

module "rds" {
  source = "./modules/rds"

  name                       = "${var.name}-db"
  vpc_id                     = data.aws_vpc.selected.id
  subnet_ids                 = [data.aws_subnet.a.id, data.aws_subnet.b.id]
  allowed_security_group_ids = [aws_security_group.ecs_tasks.id]
  db_password                = random_password.db_password.result
  min_capacity               = var.rds_min_capacity
  max_capacity               = var.rds_max_capacity
  tags                       = var.tags
}

module "elasticache" {
  source = "./modules/elasticache"

  name                       = "${var.name}-redis"
  vpc_id                     = data.aws_vpc.selected.id
  subnet_ids                 = [data.aws_subnet.a.id, data.aws_subnet.b.id]
  allowed_security_group_ids = [aws_security_group.ecs_tasks.id]
  node_type                  = var.redis_node_type
  auth_token                 = random_password.redis_auth_token.result
  tags                       = var.tags
}

module "clickhouse" {
  source = "./modules/clickhouse"

  name                       = var.name
  aws_region                 = var.aws_region
  cluster_arn                = module.ecs_cluster.cluster_arn
  cluster_name               = module.ecs_cluster.cluster_name
  namespace_arn              = module.service_discovery.namespace_id
  vpc_id                     = data.aws_vpc.selected.id
  subnet_ids                 = [data.aws_subnet.a.id, data.aws_subnet.b.id]
  allowed_security_group_ids = [aws_security_group.ecs_tasks.id]
  task_execution_role_arn    = module.iam.task_execution_role_arn
  task_role_arn              = module.iam.task_role_arns["clickhouse"]
  log_group_name             = module.ecs_cluster.log_group_name
  image_tag                  = var.clickhouse_image_tag
  password_secret_arn        = "${aws_secretsmanager_secret.this.arn}:CLICKHOUSE_PASSWORD::"
  tags                       = var.tags
}

###############################################################################
# OneUptime services
###############################################################################
# Image per service — `worker` intentionally runs the "app" image (same
# process, different role: it registers the BullMQ queue consumers instead of
# serving API traffic — see the upstream chart's worker.yaml). Reconcile the
# environment map below against the OneUptime Helm chart's values.yaml/
# ConfigMap for your target version before going to production — this covers
# the common/required variables only (see docs/deploy-aws.md's "Known
# limitations").
locals {
  image_repo = {
    nginx  = "nginx"
    app    = "app"
    home   = "home"
    worker = "app"
    probe  = "probe"
    runner = "runner"
  }

  common_environment = [
    { name = "NODE_ENV", value = "production" },
    { name = "LOG_LEVEL", value = "ERROR" },
    { name = "HOST", value = var.oneuptime_public_host },
    { name = "HTTP_PROTOCOL", value = "https" },
    { name = "DATABASE_HOST", value = module.rds.endpoint },
    { name = "DATABASE_PORT", value = tostring(module.rds.port) },
    { name = "DATABASE_NAME", value = module.rds.database_name },
    { name = "DATABASE_USERNAME", value = "postgres" },
    { name = "REDIS_HOST", value = module.elasticache.primary_endpoint_address },
    { name = "REDIS_PORT", value = tostring(module.elasticache.port) },
    { name = "CLICKHOUSE_HOST", value = module.clickhouse.native_dns_name },
    { name = "CLICKHOUSE_PORT", value = "9000" },
    { name = "CLICKHOUSE_DATABASE", value = "oneuptime" },
    { name = "CLICKHOUSE_USER", value = "oneuptime" },
  ]

  common_secrets = [
    { name = "ONEUPTIME_SECRET", valueFrom = "${aws_secretsmanager_secret.this.arn}:ONEUPTIME_SECRET::" },
    { name = "ENCRYPTION_SECRET", valueFrom = "${aws_secretsmanager_secret.this.arn}:ENCRYPTION_SECRET::" },
    { name = "DATABASE_PASSWORD", valueFrom = "${aws_secretsmanager_secret.this.arn}:DATABASE_PASSWORD::" },
    { name = "REDIS_PASSWORD", valueFrom = "${aws_secretsmanager_secret.this.arn}:REDIS_AUTH_TOKEN::" },
    { name = "CLICKHOUSE_PASSWORD", valueFrom = "${aws_secretsmanager_secret.this.arn}:CLICKHOUSE_PASSWORD::" },
  ]
}

module "services" {
  source   = "./modules/ecs-service"
  for_each = var.service_sizing

  name          = each.key
  aws_region    = var.aws_region
  cluster_arn   = module.ecs_cluster.cluster_arn
  cluster_name  = module.ecs_cluster.cluster_name
  namespace_arn = module.service_discovery.namespace_id

  image  = "docker.io/oneuptime/${local.image_repo[each.key]}:${var.image_tag}"
  cpu    = each.value.cpu
  memory = each.value.memory

  container_port = each.value.container_port
  desired_count  = each.value.desired_count

  environment = local.common_environment
  secrets     = local.common_secrets

  task_execution_role_arn = module.iam.task_execution_role_arn
  task_role_arn           = module.iam.task_role_arns[each.key]

  subnet_ids         = [data.aws_subnet.a.id, data.aws_subnet.b.id]
  security_group_ids = [aws_security_group.ecs_tasks.id]
  target_group_arn   = each.key == "nginx" ? module.alb.nginx_target_group_arn : null
  log_group_name     = module.ecs_cluster.log_group_name

  tags = var.tags

  depends_on = [module.rds, module.elasticache, module.clickhouse]
}
