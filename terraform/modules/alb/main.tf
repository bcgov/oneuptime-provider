resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Internal ALB for ${var.name} - allows HTTPS from the platform-managed VPC CIDR, egress to the nginx service."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS - perimeter fronts this ALB, the platform WAF/perimeter controls are the real boundary here, not this SG"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

data "aws_caller_identity" "this" {
  count = var.enable_access_logs ? 1 : 0
}

data "aws_region" "this" {
  count = var.enable_access_logs ? 1 : 0
}

resource "aws_s3_bucket" "alb_access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = "${var.name}-alb-logs-${data.aws_caller_identity.this[0].account_id}"

  tags = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "alb_access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "alb_access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket                  = aws_s3_bucket.alb_access_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Debugging aid only — old logs aren't worth keeping/paying for indefinitely.
resource "aws_s3_bucket_lifecycle_configuration" "alb_access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    id     = "expire-old-access-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 14
    }
  }
}

data "aws_iam_policy_document" "alb_access_logs" {
  count = var.enable_access_logs ? 1 : 0

  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.alb_access_logs[0].arn}/${var.name}/AWSLogs/${data.aws_caller_identity.this[0].account_id}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.this[0].account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:elasticloadbalancing:${data.aws_region.this[0].name}:${data.aws_caller_identity.this[0].account_id}:loadbalancer/*"]
    }
  }

  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.alb_access_logs[0].arn]
  }
}

resource "aws_s3_bucket_policy" "alb_access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id
  policy = data.aws_iam_policy_document.alb_access_logs[0].json
}

resource "aws_lb" "this" {
  name               = var.name
  internal           = true
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.alb.id]

  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_access_logs[0].bucket
      prefix  = var.name
      enabled = true
    }
  }

  tags = merge(var.tags, {
    Public     = "True"
    PublicHost = var.public_host_label
  })

  depends_on = [
    aws_s3_bucket_policy.alb_access_logs,
    aws_s3_bucket_ownership_controls.alb_access_logs,
    aws_s3_bucket_server_side_encryption_configuration.alb_access_logs,
  ]
}

resource "aws_lb_target_group" "nginx" {
  name_prefix = "nginx-"
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

  lifecycle {
    create_before_destroy = true
  }
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
