######################################################################################
# Provides
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}
######################################################################################
# Data Source
data "aws_ecrpublic_authorization_token" "token" {
  region = "us-east-1"
}

######################################################################################
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