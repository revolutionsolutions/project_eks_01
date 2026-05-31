# Provides
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      #Karpenter tag
      "karpenter.sh/discovery" = "${lower(var.client_name)}${local.region_short}-cluster01"
    }
  }
}

provider "local" {}


# Local Variables
locals {
  region_map = {
    "us-east-1" = "use1"
    "us-east-2" = "use2"
    "us-west-1" = "usw1"
    "us-west-2" = "usw2"
  }

  region_short = lookup(local.region_map, var.region, "unknown")
  cluster_name = "${lower(var.client_name)}${local.region_short}-cluster01"

  renderd_yaml = templatefile("./karpenter.yaml.tpl", {
    cluster_name = "${lower(var.client_name)}${local.region_short}-cluster01"
  })
}

# # Data Sources
data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "state-bucket-for-projects-20260531"
    key    = "yyy/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.vpc.outputs.vpc_id]
  }

  tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

######################################################################################
# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "${local.cluster_name}-role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })

}

# Attache policy to EKS role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# EKS Module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.cluster_name
  kubernetes_version = "1.34"
  iam_role_arn       = aws_iam_role.eks_cluster_role.arn

  # Access
  endpoint_public_access = true
  endpoint_private_access = false

  # Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true
  authentication_mode = "API"

  # Addons
  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    metrics-server = {}
  }


  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.aws_subnets.private.ids

  tags = {
    Name      = "${local.cluster_name}"
    Terraform = "true"
  }

  depends_on = [ aws_iam_role_policy_attachment.eks_cluster_policy_attachment ]
}

######################################################################################

# EKS Nodegroup IAM Role
resource "aws_iam_role" "eks_ngrp_iam_role" {
  name = "${local.cluster_name}-ngrp-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

# Policy attachments for EKS Node Group Role
resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  role       = aws_iam_role.eks_ngrp_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  role       = aws_iam_role.eks_ngrp_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy" {
  role       = aws_iam_role.eks_ngrp_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_node_group" "eks_ngrp" {
  cluster_name    = local.cluster_name
  node_group_name = "${local.cluster_name}-ngrp-01"
  node_role_arn   = aws_iam_role.eks_ngrp_iam_role.arn
  subnet_ids      = data.aws_subnets.private.ids

  scaling_config {
    desired_size = 3
    max_size     = 5
    min_size     = 0
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

######################################################################################

# Write Render YAML (inject variables) to a file
resource "local_file" "karpenter_yaml" {
  filename = "./karpenter.yaml"
  content = local.renderd_yaml
}