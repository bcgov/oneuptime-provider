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
    # Was originally restricted to var.vpc_cidr on the assumption that the
    # LZA perimeter ALB always forwards from an address within this VPC's
    # CIDR — in practice, confirmed in a live deployment that inbound
    # traffic did not match that assumption (likely arrives via TGW from a
    # different account/CIDR, or with the original client IP preserved) and
    # requests never reached this internal ALB. Opened to all traffic; the
    # perimeter/WAF layer in front of this ALB is still the real access
    # boundary, matching how the previous EKS ingress was exposed.
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

# --- Access logs (debugging aid) --------------------------------------------
# Off by default (var.enable_access_logs). When on, this is the fastest way
# to tell whether a request that comes back 504 even reached the ALB/nginx
# target at all: every access log line records the target's response code
# and processing time, or "-1"/"timeout" reason codes when the ALB gave up
# waiting on the target — all visible here even if nginx/app themselves
# logged nothing for that request. See:
#   aws s3 ls s3://<bucket from output alb_access_logs_bucket>/ --recursive
# Docs: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
data "aws_caller_identity" "this" {
  count = var.enable_access_logs ? 1 : 0
}

data "aws_region" "this" {
  count = var.enable_access_logs ? 1 : 0
}

resource "aws_s3_bucket" "alb_access_logs" {
  count = var.enable_access_logs ? 1 : 0

  # Bucket names are global; suffixing with the account ID keeps this
  # collision-free without requiring a user-supplied name.
  bucket = "${var.name}-alb-logs-${data.aws_caller_identity.this[0].account_id}"

  tags = var.tags
}

# Explicit rather than relying on the platform default -- the AWS doc above
# ("Step 1: Create an S3 bucket") states SSE-S3 is the *only* supported
# server-side encryption option for ALB access log buckets; a bucket
# defaulting to SSE-KMS (e.g. via an account-level default) would silently
# fail every log delivery.
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  count = var.enable_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Forces every object in the bucket to be owned by this account regardless
# of which principal wrote it (ELB's log delivery service, in this case).
# This is the setting that actually makes delivered logs visible/downloadable
# in the console: the ELB log delivery service principal writes objects
# without any ACL, so on a bucket that still has ACLs enabled (the default
# prior to April 2023) those objects can end up owned by the delivery
# service with no ACL grant back to the bucket owner, making them
# inaccessible from this account's console/CLI even though delivery
# "succeeded". BucketOwnerEnforced disables ACLs entirely and makes this a
# non-issue.
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

# Current (post-August-2022, all regions including ca-central-1) ALB access
# log bucket policy — see "Step 2: Attach a policy to your S3 bucket" in the
# AWS doc linked above. Deliberately does NOT include an
# "s3:x-amz-acl": "bucket-owner-full-control" condition: that condition only
# applies to the legacy per-region-ELB-account policy (superseded here) and
# to Outposts Zones. Adding it to this service-principal statement makes ELB's
# actual PutObject calls (which carry no such ACL header) fail the policy
# match, so no logs are ever delivered — this was the bug in the original
# version of this policy. The resource path is scoped to
# .../AWSLogs/<account_id>/* (not a bare bucket wildcard) and the
# aws:SourceAccount/aws:SourceArn conditions restrict delivery to only this
# account's ALBs, per the doc's "Security best practices".
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
    # Required by LZA's perimeter automation — see instructions.md /
    # instructions-2.md. Public=True makes this ALB reachable at
    # <PublicHost>.<account>.stratus.cloud.gov.bc.ca.
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
  # name_prefix (not name) + create_before_destroy below: aws_lb_target_group
  # is ForceNew on port changes, and a fixed name collides with the
  # about-to-be-destroyed old target group of the same name during a
  # create-before-destroy replacement (AWS target group names must be
  # unique). name_prefix lets AWS generate a unique suffix so the new and
  # old target groups can coexist briefly while the listener below is
  # repointed at the new one. Max 6 characters for name_prefix.
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

  # Without this, a port change (ForceNew) destroys the old target group
  # BEFORE creating the new one — but the listener below still references
  # the old target group's ARN at that point, so AWS refuses the delete
  # with "Target group ... is currently in use by a listener or a rule".
  # create_before_destroy makes Terraform create the new target group,
  # update the listener's default_action to point at it, and only then
  # destroy the old one.
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
