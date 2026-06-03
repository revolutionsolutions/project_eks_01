# Provides

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.46.0"
    }
  }

  required_version = ">= 1.2"
}



# S3 bucket
resource "aws_s3_bucket" "state" {
  bucket = "state-bucket-for-projects-20260603"
  force_destroy = true
}