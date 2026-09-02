# Internal ALB, Terraform-managed (LZA "Pattern B" from ../../instructions.md
# / ../../instructions-2.md) — unlike the previous EKS setup, there's no
# Kubernetes Ingress/AWS Load Balancer Controller here, so the ALB, target
# group, listener and health-check rule are plain Terraform resources.
#
# LZA requirements this satisfies:
#   - Public=True tag (+ PublicHost) so the platform's perimeter automation
#     discovers and fronts this ALB publicly.
#   - A listener rule at /bcgovhealthcheck returning a fixed 200 — probed by
#     the perimeter public ALB.
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Internal ALB for ${var.name} - allows HTTPS from the platform-managed VPC CIDR, egress to the nginx service."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from within the VPC (perimeter ALB reaches this internal ALB over the VPC/TGW path)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description     = "To the nginx Fargate task"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [var.nginx_security_group_id]
  }

  tags = var.tags
}

resource "aws_lb" "this" {
  name               = var.name
  internal           = true
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.alb.id]

  tags = merge(var.tags, {
    # Required by LZA's perimeter automation — see instructions.md /
    # instructions-2.md. Public=True makes this ALB reachable at
    # <PublicHost>.<account>.stratus.cloud.gov.bc.ca.
    Public     = "True"
    PublicHost = var.public_host_label
  })
}

resource "aws_lb_target_group" "nginx" {
  name        = "${var.name}-nginx"
  port        = var.nginx_container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/status/live"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx.arn
  }
}

# Perimeter health probe: fixed 200 at /bcgovhealthcheck, served directly by
# the ALB (never reaches nginx/ECS).
resource "aws_lb_listener_rule" "health_fixed_200" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1

  action {
    type = "fixed-response"
    fixed_response {
      status_code  = "200"
      content_type = "text/plain"
      message_body = "ok"
    }
  }

  condition {
    path_pattern {
      values = ["/bcgovhealthcheck"]
    }
  }
}
