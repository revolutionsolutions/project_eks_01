# data "aws_eks_cluster" "eks" {
#   name = module.eks.cluster_name
# }

data "aws_eks_cluster_auth" "eks" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = module.eks.cluster_endpoint
    token                  = data.aws_eks_cluster_auth.eks.token
  }
  
}