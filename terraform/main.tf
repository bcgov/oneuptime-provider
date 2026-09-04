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

# A freshly-created Cloud Map namespace isn't immediately visible to ECS's
# own control plane; the exact delay isn't documented by AWS. There's no
# AWS API to directly ask "is this ready for ECS yet", so a plain fixed
# delay (via the `time_sleep` resource, no local shell/AWS CLI dependency)
# is the standard, most reliable way to handle this — not a custom polling
# script, which just trades one guess for a different kind of fragility
# (shell portability, requiring the AWS CLI to be installed/configured on
# whichever machine runs `terraform apply`). Every ECS service depends on
# this instead of the namespace module directly.
resource "time_sleep" "namespace_propagation" {
  depends_on      = [module.service_discovery]
  create_duration = "60s"
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

# Shared secret the probe presents when self-registering with the app
# (App/FeatureSet/Telemetry/API/ProbeIngest/Register.ts validates it) — must
# match on both the app and probe services. See
# Common/Server/EnvironmentConfig.ts (RegisterProbeKey) upstream.
resource "random_password" "register_probe_key" {
  length  = 32
  special = false
}

# The probe's own auth key, generated once and used for its initial
# self-registration call and subsequent alive/status checks (see
# Probe/Services/Register.ts). Unlike REGISTER_PROBE_KEY this does not need
# to be known ahead of time by the app — the app creates the Probe record on
# first successful registration.
resource "random_password" "probe_key" {
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
    REGISTER_PROBE_KEY  = random_password.register_probe_key.result
    PROBE_KEY           = random_password.probe_key.result
  })
}

###############################################################################
# IAM
###############################################################################

module "iam" {
  source = "./modules/iam"

  name          = var.name
  secret_arn    = aws_secretsmanager_secret.this.arn
  service_names = setunion(toset(keys(var.service_sizing)), ["clickhouse", "migrate"])
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
  namespace_arn              = module.service_discovery.namespace_arn
  namespace_id               = module.service_discovery.namespace_id
  namespace_name             = module.service_discovery.namespace_name
  vpc_id                     = data.aws_vpc.selected.id
  subnet_ids                 = [data.aws_subnet.a.id, data.aws_subnet.b.id]
  allowed_security_group_ids = [aws_security_group.ecs_tasks.id]
  task_execution_role_arn    = module.iam.task_execution_role_arn
  task_role_arn              = module.iam.task_role_arns["clickhouse"]
  log_group_name             = module.ecs_cluster.log_group_name
  image_tag                  = var.clickhouse_image_tag
  password_secret_arn        = "${aws_secretsmanager_secret.this.arn}:CLICKHOUSE_PASSWORD::"
  tags                       = var.tags

  depends_on = [time_sleep.namespace_propagation]
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
    # Required by nginx's default.conf.template (Nginx/default.conf.template
    # in the upstream repo), which does `set $backend_app
    # http://${SERVER_APP_HOSTNAME}:${APP_PORT};` and the equivalent for
    # home. If these are absent, envsubst leaves the literal "${VAR}" text in
    # place and nginx then fails with "unknown ... variable" trying to parse
    # it as an nginx variable reference. Hostnames match the ECS Service
    # Connect `dns_name` (== each service's `var.name`, see
    # modules/ecs-service/main.tf) so these resolve inside the Cloud Map
    # namespace. Also applied to every service (not just nginx) since the
    # app/worker Node processes read the same vars for internal URLs (see
    # Common/Server/EnvironmentConfig.ts upstream) and otherwise silently
    # fall back to "localhost".
    { name = "SERVER_APP_HOSTNAME", value = "app" },
    { name = "SERVER_HOME_HOSTNAME", value = "home" },
    { name = "APP_PORT", value = tostring(var.service_sizing["app"].container_port) },
    { name = "HOME_PORT", value = tostring(var.service_sizing["home"].container_port) },
    # Referenced unconditionally in default.conf.template
    # (`set $billing_enabled ${BILLING_ENABLED};`); unlike
    # NGINX_INGEST_ACCESS_LOG this has no internal nginx-side fallback map,
    # so it must always be set to avoid the same "unknown variable" failure.
    { name = "BILLING_ENABLED", value = "false" },
    # App/Index.ts (and Workers/Index.ts) run full TypeORM schema sync +
    # Postgres/ClickHouse data migrations on every boot UNLESS this is
    # explicitly "false" (Common/Server/EnvironmentConfig.ts:
    # `RunDatabaseMigrationsOnBoot = process.env["RUN_DATABASE_MIGRATIONS_ON_BOOT"]
    # !== "false"` — i.e. it defaults to true). Upstream's Helm chart always
    # runs migrations exactly once in a dedicated one-off `migrate` Job (see
    # migrate-job.yaml) and sets this to "false" on every runtime pod
    # (app/worker/nginx) specifically to prevent that: with it unset, every
    # app/worker replica/redeploy independently runs migrations against the
    # same schema with no coordinating advisory lock, which can race,
    # deadlock on DDL locks, or simply leave a replica silently hung mid-
    # migration with no further log output (exactly the "socket hang up" /
    # blank-after-boot symptom this repo hit). The `migrate` standalone ECS
    # task definition below (run manually, once, via `aws ecs run-task`)
    # is this repo's equivalent of that Job.
    { name = "RUN_DATABASE_MIGRATIONS_ON_BOOT", value = "false" },
  ]

  common_secrets = [
    { name = "ONEUPTIME_SECRET", valueFrom = "${aws_secretsmanager_secret.this.arn}:ONEUPTIME_SECRET::" },
    { name = "ENCRYPTION_SECRET", valueFrom = "${aws_secretsmanager_secret.this.arn}:ENCRYPTION_SECRET::" },
    { name = "DATABASE_PASSWORD", valueFrom = "${aws_secretsmanager_secret.this.arn}:DATABASE_PASSWORD::" },
    { name = "REDIS_PASSWORD", valueFrom = "${aws_secretsmanager_secret.this.arn}:REDIS_AUTH_TOKEN::" },
    { name = "CLICKHOUSE_PASSWORD", valueFrom = "${aws_secretsmanager_secret.this.arn}:CLICKHOUSE_PASSWORD::" },
  ]

  # Per-service env var overrides, merged on top of common_environment.
  # nginx's entrypoint (Nginx/envsubst-on-templates.sh in the upstream repo)
  # runs `envsubst` against its config template, which references
  # NGINX_LISTEN_ADDRESS/NGINX_LISTEN_OPTIONS directly in `listen` directives
  # (see Nginx/default.conf.template). envsubst only replaces variables that
  # are actually *set* in the environment, even to an empty string — leaving
  # them unset means the literal "${NGINX_LISTEN_ADDRESS}" text is left in
  # nginx.conf, which nginx then fails to parse as a `listen` address. The
  # upstream Helm chart always sets both (usually to "") for exactly this
  # reason — see HelmChart/Public/oneuptime/templates/nginx.yaml.
  # probe/runner hard-exit at startup (Probe/Config.ts: `if
  # (!process.env["PROBE_INGEST_URL"] && !process.env["ONEUPTIME_URL"]) {
  # process.exit(1) }`) unless ONEUPTIME_URL points at the app service. The
  # upstream Helm chart sets this explicitly per-service (probe.yaml /
  # runner.yaml) to the in-cluster app Service URL — mirrored here via the
  # ECS Service Connect DNS name for "app".
  oneuptime_internal_url = "http://app:${var.service_sizing["app"].container_port}"

  per_service_environment = {
    nginx = [
      { name = "NGINX_LISTEN_ADDRESS", value = "" },
      { name = "NGINX_LISTEN_OPTIONS", value = "" },
    ]
    probe = [
      { name = "ONEUPTIME_URL", value = local.oneuptime_internal_url },
    ]
    runner = [
      { name = "ONEUPTIME_URL", value = local.oneuptime_internal_url },
    ]
  }

  # Secrets-Manager-backed per-service overrides, merged on top of
  # common_secrets. REGISTER_PROBE_KEY is a shared secret: "app" validates it
  # (App/FeatureSet/Telemetry/API/ProbeIngest/Register.ts) and "probe" sends
  # it when self-registering (Probe/Services/Register.ts) — both must read
  # the same Secrets Manager value. PROBE_KEY is the probe's own generated
  # auth key, only needed by probe itself.
  per_service_secrets = {
    app = [
      { name = "REGISTER_PROBE_KEY", valueFrom = "${aws_secretsmanager_secret.this.arn}:REGISTER_PROBE_KEY::" },
    ]
    probe = [
      { name = "REGISTER_PROBE_KEY", valueFrom = "${aws_secretsmanager_secret.this.arn}:REGISTER_PROBE_KEY::" },
      { name = "PROBE_KEY", valueFrom = "${aws_secretsmanager_secret.this.arn}:PROBE_KEY::" },
    ]
  }
}

module "services" {
  source   = "./modules/ecs-service"
  for_each = var.service_sizing

  name          = each.key
  aws_region    = var.aws_region
  cluster_arn   = module.ecs_cluster.cluster_arn
  cluster_name  = module.ecs_cluster.cluster_name
  namespace_arn = module.service_discovery.namespace_arn

  image  = "docker.io/oneuptime/${local.image_repo[each.key]}:${var.image_tag}"
  cpu    = each.value.cpu
  memory = each.value.memory

  container_port = each.value.container_port
  desired_count  = each.value.desired_count

  environment = concat(local.common_environment, lookup(local.per_service_environment, each.key, []))
  secrets     = concat(local.common_secrets, lookup(local.per_service_secrets, each.key, []))

  task_execution_role_arn = module.iam.task_execution_role_arn
  task_role_arn           = module.iam.task_role_arns[each.key]

  subnet_ids         = [data.aws_subnet.a.id, data.aws_subnet.b.id]
  security_group_ids = [aws_security_group.ecs_tasks.id]
  target_group_arn   = each.key == "nginx" ? module.alb.nginx_target_group_arn : null
  log_group_name     = module.ecs_cluster.log_group_name

  tags = var.tags

  depends_on = [module.rds, module.elasticache, module.clickhouse, time_sleep.namespace_propagation]
}

###############################################################################
# One-off database migration task
###############################################################################
# Standalone ECS task definition (no aws_ecs_service — this is not a
# long-running service). Mirrors the upstream Helm chart's dedicated
# `migrate` Job (migrate-job.yaml): runs `npm run migrate` (App/Migrate.ts)
# once against the "app" image to apply Postgres/ClickHouse schema + data
# migrations, so runtime services (app/worker/nginx, all with
# RUN_DATABASE_MIGRATIONS_ON_BOOT=false above) never race each other running
# migrations concurrently on boot.
#
# Run manually after every `terraform apply` that changes the image tag or
# on first deploy, BEFORE relying on app/worker being healthy:
#
#   aws ecs run-task \
#     --cluster <ecs_cluster_name output> \
#     --task-definition <migrate_task_definition_arn output> \
#     --launch-type FARGATE \
#     --network-configuration "awsvpcConfiguration={subnets=[<subnet ids>],securityGroups=[<ecs task SG>],assignPublicIp=DISABLED}"
#
# then poll with `aws ecs describe-tasks` until it exits with code 0 before
# force-deploying/restarting app or worker.
resource "aws_ecs_task_definition" "migrate" {
  family                   = "${var.name}-migrate"
  execution_role_arn       = module.iam.task_execution_role_arn
  task_role_arn            = module.iam.task_role_arns["migrate"]
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  tags                     = var.tags

  container_definitions = jsonencode([
    {
      name                   = "migrate"
      image                  = "docker.io/oneuptime/app:${var.image_tag}"
      essential              = true
      readonlyRootFilesystem = false
      workingDirectory       = "/usr/src/app"
      command                = ["npm", "run", "migrate"]
      # RUN_DATABASE_MIGRATIONS_ON_BOOT=false (in common_environment) has no
      # effect on this script — App/Migrate.ts always runs migrations
      # unconditionally when invoked directly via `npm run migrate`.
      # CLICKHOUSE_HOST is overridden here (vs. common_environment's
      # "clickhouse" Service Connect alias) because this task is started
      # standalone via `aws ecs run-task`, not as part of an
      # aws_ecs_service — it's never a Service Connect client, so the
      # "clickhouse" short name doesn't resolve for it (getaddrinfo
      # ENOTFOUND). The classic Cloud Map discovery record does resolve
      # from any task in the VPC regardless of Service Connect membership.
      environment = concat(
        [for e in local.common_environment : e if e.name != "CLICKHOUSE_HOST"],
        [{ name = "CLICKHOUSE_HOST", value = module.clickhouse.native_discovery_dns_name }]
      )
      secrets = local.common_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = module.ecs_cluster.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "migrate"
        }
      }
    }
  ])

  depends_on = [module.rds]
}
