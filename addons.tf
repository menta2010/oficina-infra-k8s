# Componentes de plataforma instalados no cluster via Helm.

# metrics-server: fornece CPU/memoria dos pods ao HPA
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"
  namespace  = "kube-system"

  depends_on = [aws_eks_node_group.app]
}

# Cluster Autoscaler: quando o HPA cria pods que nao cabem nos nos atuais, sobe novos nos
# (ate node_max_size) e remove nos ociosos depois.
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.43.2"
  namespace  = "kube-system"

  set {
    name  = "autoDiscovery.clusterName"
    value = aws_eks_cluster.this.name
  }
  set {
    name  = "awsRegion"
    value = var.aws_region
  }
  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "5m"
  }

  depends_on = [aws_eks_node_group.app]
}

# New Relic: metricas de nos/pods (CPU, memoria), eventos do Kubernetes e estado dos deployments
resource "helm_release" "newrelic" {
  count            = var.newrelic_license_key == "" ? 0 : 1
  name             = "newrelic-bundle"
  repository       = "https://helm-charts.newrelic.com"
  chart            = "nri-bundle"
  version          = "5.0.97"
  namespace        = "newrelic"
  create_namespace = true

  set {
    name  = "global.cluster"
    value = aws_eks_cluster.this.name
  }
  set_sensitive {
    name  = "global.licenseKey"
    value = var.newrelic_license_key
  }
  set {
    name  = "newrelic-infrastructure.privileged"
    value = "true"
  }
  set {
    name  = "kube-state-metrics.enabled"
    value = "true"
  }
  set {
    name  = "nri-kube-events.enabled"
    value = "true"
  }
  # Logs da API vao pelo agente APM (logs in context com o trace); sem duplicar via fluent-bit
  set {
    name  = "newrelic-logging.enabled"
    value = "false"
  }

  depends_on = [aws_eks_node_group.app]
}
