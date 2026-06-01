# Provides

terraform {
  backend "s3" {
    bucket = "state-bucket-for-projects-20260601"
    key    = "yyy/eks/terraform.tfstate"
    region = "us-east-1"
  }


  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.46.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.2"
    }
  }

  required_version = ">= 1.2"
}