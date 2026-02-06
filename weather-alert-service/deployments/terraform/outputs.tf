output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "URL of the Application Load Balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379"
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.app.name
}

output "secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret for API key"
  value       = aws_secretsmanager_secret.openweather_api_key.arn
}
