resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [ aws_eks_node_group.eks_ngrp ]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
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

  depends_on = [ kubernetes_namespace_v1.argocd]
}