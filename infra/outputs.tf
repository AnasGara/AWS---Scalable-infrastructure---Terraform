output "application_url" {
  value = "https://${var.domain_name}"
}
output "alb_dns_name" {
  value = module.service.alb_dns_name
}
output "autoscaling_group_name" {
  value = module.service.asg_name
}
output "database_endpoint" {
  value = module.database.endpoint
}
output "database_secret_arn" {
  value       = module.database.secret_arn
  description = "Reference only; database secret values are never read by Terraform."
}
output "vpc_id" {
  value = module.network.vpc_id
}
