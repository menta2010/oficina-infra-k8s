# Caminho da requisicao:
#   Cliente --HTTPS--> API Gateway (HTTP API, throttling, logs de acesso)
#     |- POST /auth/cpf e /auth/login --> Lambda de autenticacao (rotas criadas no repo oficina-lambda-auth)
#     '- demais rotas --> VPC Link --> NLB interno --> NodePort 30080 nos nos do EKS --> pods da API

# --- NLB interno na frente do cluster ----------------------------------------

resource "aws_lb" "api" {
  name               = "${local.prefixo}-api-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = module.vpc.private_subnets
}

resource "aws_lb_target_group" "api" {
  name        = "${local.prefixo}-api"
  port        = var.app_node_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  health_check {
    protocol            = "HTTP"
    path                = "/health/ready"
    port                = tostring(var.app_node_port)
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# Os nos do node group entram e saem do target group automaticamente com o autoscaling
resource "aws_autoscaling_attachment" "api" {
  autoscaling_group_name = aws_eks_node_group.app.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.api.arn
}

# --- API Gateway (HTTP API) ---------------------------------------------------

resource "aws_apigatewayv2_api" "this" {
  name          = "${local.prefixo}-api"
  protocol_type = "HTTP"
  description   = "Porta de entrada da oficina: autenticacao (Lambda) e API de ordens de servico (EKS)"

  cors_configuration {
    allow_origins  = ["*"]
    allow_methods  = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers  = ["authorization", "content-type", "x-correlation-id", "x-webhook-token"]
    expose_headers = ["x-correlation-id"]
  }
}

resource "aws_security_group" "vpc_link" {
  name        = "${local.prefixo}-vpc-link"
  description = "VPC Link do API Gateway ate o NLB interno"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${local.prefixo}-vpc-link"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_link.id]
}

resource "aws_apigatewayv2_integration" "app" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.api.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id

  # Propaga o id da requisicao do gateway como correlationId quando o cliente nao mandar um
  request_parameters = {
    "overwrite:header.x-gateway-request-id" = "$context.requestId"
  }
}

# Tudo que nao for /auth/* vai para a API no EKS
resource "aws_apigatewayv2_route" "app" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.app.id}"
}

resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/aws/apigateway/${local.prefixo}-api"
  retention_in_days = 7
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  # Rate limit global: acima disso o gateway responde 429 sem tocar no cluster
  default_route_settings {
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit
  }

  # O limite mais baixo das rotas /auth/* (forca bruta de CPF/senha) e aplicado pelo repositorio
  # oficina-lambda-auth logo apos criar essas rotas: a AWS nao aceita configurar rota inexistente.

  # Log de acesso em JSON: latencia, status e integracao por requisicao (vai para o New Relic)
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.gateway.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      correlationId      = "$request.header.x-correlation-id"
      ip                 = "$context.identity.sourceIp"
      method             = "$context.httpMethod"
      route              = "$context.routeKey"
      path               = "$context.path"
      status             = "$context.status"
      latencyMs          = "$context.responseLatency"
      integrationLatency = "$context.integrationLatency"
      integrationStatus  = "$context.integrationStatus"
      error              = "$context.error.message"
    })
  }

  lifecycle {
    # rotas /auth/* e seus limites sao gerenciados pelo repositorio da Lambda depois deste apply
    ignore_changes = [deployment_id, route_settings]
  }
}
