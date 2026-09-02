# Route 53 Private Hosted Zone, associated with the platform VPC — the ECS
# equivalent of the EKS setup's coredns.tf rewrite.
#
# OneUptime's server-side rendering makes self-referential API calls back to
# itself using its own PUBLIC hostname (LZA's perimeter hostname). This
# platform's VPC has no Internet Gateway, so ECS tasks have no route to the
# public internet — a task calling back out to its own public hostname just
# hangs until it times out (ETIMEDOUT), breaking SSR.
#
# Fix: a private hosted zone for the exact public hostname, associated only
# with this VPC, with an alias record pointing at the internal ALB. Inside
# the VPC (i.e. from every ECS task), DNS resolution for that hostname now
# returns the internal ALB directly — never leaving the VPC. Outside the
# VPC, public DNS resolution is untouched (still LZA's perimeter automation),
# so browsers keep resolving/reaching the real public hostname as before.
resource "aws_route53_zone" "private" {
  name = var.public_hostname

  vpc {
    vpc_id = var.vpc_id
  }

  tags = var.tags
}

resource "aws_route53_record" "alias_to_alb" {
  zone_id = aws_route53_zone.private.zone_id
  name    = var.public_hostname
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
