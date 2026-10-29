locals {
  cria_role_cluster = var.cluster_role_arn == ""
  cria_role_nos     = var.node_role_arn == ""
  cluster_role_arn  = local.cria_role_cluster ? aws_iam_role.cluster[0].arn : var.cluster_role_arn
  node_role_arn     = local.cria_role_nos ? aws_iam_role.nos[0].arn : var.node_role_arn
}

# --- IAM (somente quando nao forem informadas roles existentes) ----------------

resource "aws_iam_role" "cluster" {
  count = local.cria_role_cluster ? 1 : 0
  name  = "${local.cluster_name}-cluster"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  count      = local.cria_role_cluster ? 1 : 0
  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "nos" {
  count = local.cria_role_nos ? 1 : 0
  name  = "${local.cluster_name}-nodes"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "nos" {
  for_each = local.cria_role_nos ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]) : toset([])
  role       = aws_iam_role.nos[0].name
  policy_arn = each.value
}

# Permissoes extras dos nos: Cluster Autoscaler ajustar o node group e a API publicar no SNS.
# Em producao real o ideal e IRSA (role por service account); ver ADR-007.
resource "aws_iam_role_policy" "nos_extras" {
  count = local.cria_role_nos ? 1 : 0
  name  = "autoscaler-e-sns"
  role  = aws_iam_role.nos[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups", "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations", "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags", "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup", "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes", "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.notificacoes_os.arn
      }
    ]
  })
}

# --- Cluster ------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  version  = var.kubernetes_version
  role_arn = local.cluster_role_arn

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_private_access = true
    endpoint_public_access  = true # o pipeline (GitHub Actions) aplica os manifests
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = ["api", "audit"]

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# IMDSv2 obrigatorio e hop limit 2: os pods (um "salto" a mais que o no) precisam alcancar o
# metadata da instancia para usar a credencial da role do no (ex.: publicar no SNS).
resource "aws_launch_template" "nos" {
  name_prefix = "${local.prefixo}-nos-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.prefixo}-no-eks" }
  }
}

resource "aws_eks_node_group" "app" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.prefixo}-app"
  node_role_arn   = local.node_role_arn
  subnet_ids      = module.vpc.private_subnets
  instance_types  = var.node_instance_types
  capacity_type   = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.nos.id
    version = aws_launch_template.nos.latest_version
  }

  # Escalabilidade horizontal dos nos: o Cluster Autoscaler move o desired entre min e max
  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = { workload = "oficina-api" }

  tags = {
    "k8s.io/cluster-autoscaler/enabled"               = "true"
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size] # o autoscaler e dono do desired
  }

  depends_on = [aws_iam_role_policy_attachment.nos]
}

# Trafego do NLB interno ate o NodePort da API nos nos
resource "aws_vpc_security_group_ingress_rule" "nlb_para_nodeport" {
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  cidr_ipv4         = var.vpc_cidr
  from_port         = var.app_node_port
  to_port           = var.app_node_port
  ip_protocol       = "tcp"
  description       = "NLB interno para o NodePort da API"
}
