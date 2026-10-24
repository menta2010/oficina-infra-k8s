output "api_endpoint" {
  description = "URL publica do API Gateway (base de todas as chamadas)"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "swagger_url" {
  value = "${aws_apigatewayv2_api.this.api_endpoint}/swagger"
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "jwt_secret_arn" {
  value = aws_secretsmanager_secret.jwt.arn
}

output "webhook_secret_arn" {
  value = aws_secretsmanager_secret.webhook.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.notificacoes_os.arn
}

output "app_node_port" {
  value = var.app_node_port
}
