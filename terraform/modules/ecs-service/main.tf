# Generic ECS Fargate service module, instantiated once per OneUptime
# microservice in the root module (nginx, app, home, worker, probe, runner).
#
# Uses ECS Service Connect (not raw Cloud Map) for east-west DNS — the ECS
# equivalent of Kubernetes in-cluster Service DNS. Every service joins the
# shared Cloud Map namespace as a *client* (so it can resolve other
# services' short names, e.g. `http://app:3002`); services that take inbound
# traffic from siblings (set `service_connect_port_name`) additionally
# register themselves so their short name resolves.
resource "aws_ecs_task_definition" "this" {
  family                   = "${var.cluster_name}-${var.name}"
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  tags                     = var.tags

  container_definitions = jsonencode([
    {
      name                   = var.name
      image                  = var.image
      essential              = true
      readonlyRootFilesystem = false
      portMappings = var.container_port == null ? [] : [
        {
          name          = var.name
          protocol      = "tcp"
          containerPort = var.container_port
          hostPort      = var.container_port
        }
      ]
      environment = var.environment
      secrets     = var.secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = var.name
        }
      }
    }
  ])
}

resource "aws_ecs_service" "this" {
  name                              = var.name
  cluster                           = var.cluster_arn
  task_definition                   = aws_ecs_task_definition.this.arn
  desired_count                     = var.desired_count
  enable_ecs_managed_tags           = true
  propagate_tags                    = "TASK_DEFINITION"
  health_check_grace_period_seconds = var.target_group_arn == null ? null : 60
  wait_for_steady_state             = false

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 100
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [1]
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  service_connect_configuration {
    enabled   = true
    namespace = var.namespace_arn

    dynamic "service" {
      for_each = var.container_port == null ? [] : [1]
      content {
        port_name      = var.name
        discovery_name = var.name

        client_alias {
          port     = var.container_port
          dns_name = var.name
        }
      }
    }

    log_configuration {
      log_driver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "${var.name}-service-connect"
      }
    }
  }

  tags = var.tags
}
