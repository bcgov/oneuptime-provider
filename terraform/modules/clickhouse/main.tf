# Self-hosted ClickHouse on Fargate, backed by EFS for persistence — there is
# no AWS-managed ClickHouse offering. Single instance only: no
# replication/Keeper quorum, no automatic failover. Acceptable for this
# repo's dev/small scope; see docs/deploy-aws.md's "Known limitations"
# section before using this for anything you can't afford to lose/rebuild.
resource "aws_security_group" "this" {
  name        = "${var.name}-clickhouse"
  description = "ClickHouse SG for ${var.name}: ingress from OneUptime app/worker ECS tasks, plus NFS from itself for EFS."
  vpc_id      = var.vpc_id

  ingress {
    description     = "ClickHouse native protocol from OneUptime ECS tasks"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  ingress {
    description     = "ClickHouse HTTP interface from OneUptime ECS tasks"
    from_port       = 8123
    to_port         = 8123
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

resource "aws_security_group" "efs" {
  name        = "${var.name}-clickhouse-efs"
  description = "EFS mount targets for ${var.name} ClickHouse data - NFS ingress only from the ClickHouse task SG."
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from the ClickHouse Fargate task"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.this.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_efs_file_system" "this" {
  creation_token   = "${var.name}-clickhouse"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = var.tags
}

resource "aws_efs_mount_target" "this" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "this" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 101 # clickhouse user in the official clickhouse/clickhouse-server image
    gid = 101
  }

  root_directory {
    path = "/clickhouse-data"
    creation_info {
      owner_uid   = 101
      owner_gid   = 101
      permissions = "0755"
    }
  }

  tags = var.tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.cluster_name}-clickhouse"
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  tags                     = var.tags

  volume {
    name = "clickhouse-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.this.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.this.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "clickhouse"
      image     = "clickhouse/clickhouse-server:${var.image_tag}"
      essential = true
      portMappings = [
        { name = "clickhouse-native", protocol = "tcp", containerPort = 9000, hostPort = 9000 },
        { name = "clickhouse-http", protocol = "tcp", containerPort = 8123, hostPort = 8123 },
      ]
      mountPoints = [
        {
          sourceVolume  = "clickhouse-data"
          containerPath = "/var/lib/clickhouse"
          readOnly      = false
        }
      ]
      environment = [
        { name = "CLICKHOUSE_USER", value = var.username },
        { name = "CLICKHOUSE_DB", value = var.database_name },
      ]
      secrets = [
        { name = "CLICKHOUSE_PASSWORD", valueFrom = var.password_secret_arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "clickhouse"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "this" {
  name            = "clickhouse"
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1 # single instance only — see module header

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 100
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = var.namespace_arn

    service {
      port_name      = "clickhouse-native"
      discovery_name = "clickhouse"

      client_alias {
        port     = 9000
        dns_name = "clickhouse"
      }
    }

    service {
      port_name      = "clickhouse-http"
      discovery_name = "clickhouse-http"

      client_alias {
        port     = 8123
        dns_name = "clickhouse-http"
      }
    }

    log_configuration {
      log_driver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "clickhouse-service-connect"
      }
    }
  }

  tags = var.tags
}
