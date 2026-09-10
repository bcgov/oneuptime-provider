output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "nginx_target_group_arn" {
  value = aws_lb_target_group.nginx.arn
}

output "alb_access_logs_bucket" {
  description = "S3 bucket receiving ALB access logs, or null when disabled (var.enable_access_logs)."
  value       = var.enable_access_logs ? aws_s3_bucket.alb_access_logs[0].bucket : null
}
