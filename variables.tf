variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "oficina"
}

variable "environment" {
  description = "Ambiente: homolog ou prod"
  type        = string

  validation {
    condition     = contains(["homolog", "prod"], var.environment)
    error_message = "environment deve ser homolog ou prod."
  }
}

# --- Rede ---------------------------------------------------------------------

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "az_count" {
  description = "Quantidade de zonas de disponibilidade (EKS exige pelo menos 2)"
  type        = number
  default     = 2
}

# --- EKS ----------------------------------------------------------------------

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  description = "Teto do Cluster Autoscaler: novos nos sobem quando o HPA cria pods que nao cabem"
  type        = number
  default     = 4
}

variable "cluster_role_arn" {
  description = "Role existente para o cluster (AWS Academy: LabRole). Vazio = o Terraform cria."
  type        = string
  default     = ""
}

variable "node_role_arn" {
  description = "Role existente para os nos (AWS Academy: LabRole). Vazio = o Terraform cria."
  type        = string
  default     = ""
}

variable "app_node_port" {
  description = "NodePort fixo do Service da API; o NLB interno encaminha para ele"
  type        = number
  default     = 30080
}

# --- API Gateway --------------------------------------------------------------

variable "throttling_rate_limit" {
  description = "Requisicoes por segundo sustentadas em todo o gateway (rate limit)"
  type        = number
  default     = 50
}

variable "throttling_burst_limit" {
  description = "Rajada maxima aceita antes do 429"
  type        = number
  default     = 100
}


# --- Notificacoes e observabilidade -------------------------------------------

variable "notification_email" {
  description = "E-mail inscrito no topico SNS de notificacoes de OS (confirmacao chega por e-mail). Vazio = sem assinatura."
  type        = string
  default     = ""
}

variable "newrelic_license_key" {
  description = "License key (ingest) do New Relic. Vazio = nao instala a integracao Kubernetes."
  type        = string
  default     = ""
  sensitive   = true
}
