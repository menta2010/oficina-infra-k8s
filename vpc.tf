locals {
  prefixo      = "${var.project}-${var.environment}"
  cluster_name = "${local.prefixo}-eks"
  azs          = slice(data.aws_availability_zones.disponiveis.names, 0, var.az_count)
}

data "aws_availability_zones" "disponiveis" {
  state = "available"
}

# VPC com subnets publicas (NAT e balanceadores publicos) e privadas (nos do EKS, NLB interno,
# RDS e Lambdas). As tags Name/Tier sao o contrato usado pelos repositorios de banco e da Lambda.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${local.prefixo}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = true # um NAT so para reduzir custo (ver ADR-007)
  enable_dns_hostnames = true
  enable_dns_support   = true

  private_subnet_tags = {
    Tier                                          = "private"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  public_subnet_tags = {
    Tier                                          = "public"
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}
