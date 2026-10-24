# --- Segredo do JWT (compartilhado entre a Lambda que emite e a API que valida) ---

resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "${var.project}/${var.environment}/jwt"
  description             = "Chave HS256 dos tokens da oficina (${var.environment})"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = random_password.jwt.result
}

# Token de servico do webhook de aprovacao de orcamento
resource "random_password" "webhook" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "webhook" {
  name                    = "${var.project}/${var.environment}/webhook"
  description             = "Token do webhook de aprovacao de orcamento (${var.environment})"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "webhook" {
  secret_id     = aws_secretsmanager_secret.webhook.id
  secret_string = random_password.webhook.result
}

# --- Notificacoes serverless (SNS) --------------------------------------------

resource "aws_sns_topic" "notificacoes_os" {
  name = "${local.prefixo}-notificacoes-os"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.notificacoes_os.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --- Repositorio de imagens da API ---------------------------------------------

resource "aws_ecr_repository" "api" {
  name                 = "${local.prefixo}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true # varredura de vulnerabilidades a cada push
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantem as 15 imagens mais recentes"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 15 }
      action       = { type = "expire" }
    }]
  })
}
