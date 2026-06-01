resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"

#  version = "7.x.x" # pin version

  values = [
    yamlencode({
      server = {
        replicas = 2
      }
      repoServer = {
        replicas = 2
      }
      applicationSet = {
        replicas = 2
      }
      redis = {
        enabled = true
      }
    })
  ]
}