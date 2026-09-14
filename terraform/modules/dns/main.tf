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
