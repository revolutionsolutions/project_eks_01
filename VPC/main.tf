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

# Local Variables
locals {
  region_map = {
    "us-east-1" = "use1"
    "us-east-2" = "use2"
    "us-west-1" = "usw1"
    "us-west-2" = "usw2"
  }

  region_short = lookup(local.region_map, var.region, "unknown")
  vpc_name     = "${lower(var.client_name)}${local.region_short}-vpc"


  public_subnet_names = [
    for az in slice(data.aws_availability_zones.available.names, 0, 2) :
    "${lower(var.client_name)}${local.region_short}-public-${az}"
  ]

  private_subnet_names = [
    for az in slice(data.aws_availability_zones.available.names, 0, 2) :
    "${lower(var.client_name)}${local.region_short}-private-${az}"
  ]

}

# Data Sources
data "aws_availability_zones" "available" {}

# VPC
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.vpc_name
  cidr = "10.0.0.0/16"

  tags = {
    Terraform   = "true"
    Environment = "${var.client_name}"
  }
}

resource "aws_subnet" "private_zone1" {
  vpc_id            = module.vpc.vpc_id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    "Name"                                                 = "${local.private_subnet_names[0]}"
    "kubernetes.io/role/internal-elb"                      = "1"
  }
}

resource "aws_subnet" "private_zone2" {
  vpc_id            = module.vpc.vpc_id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    "Name"                                                 = "${local.private_subnet_names[1]}"
    "kubernetes.io/role/internal-elb"                      = "1"
  }
}

resource "aws_subnet" "public_zone1" {
  vpc_id                  = module.vpc.vpc_id
  cidr_block              = "10.0.101.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    "Name"                                                 = "${local.private_subnet_names[0]}"
    "kubernetes.io/role/elb"                               = "1"
  }
}

resource "aws_subnet" "public_zone2" {
  vpc_id                  = module.vpc.vpc_id
  cidr_block              = "10.0.102.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    "Name"                                                 = "${local.private_subnet_names[1]}"
    "kubernetes.io/role/elb"                               = "1"
  }
}

# # VPC
# module "vpc" {
#   source = "terraform-aws-modules/vpc/aws"
#   version = "~> 6.0"

#   name = local.vpc_name
#   cidr = "10.0.0.0/16"

#   #azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
#   azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
#   private_subnets      = ["10.0.1.0/24", "10.0.2.0/24"]
#   private_subnet_names = local.private_subnet_names
#   public_subnets       = ["10.0.101.0/24", "10.0.102.0/24"]
#   public_subnet_names  = local.public_subnet_names

#   manage_default_route_table = false
#   default_route_table_routes = []

#   enable_nat_gateway     = false
#   create_igw = false
  
#   create_multiple_public_route_tables  = false
#   create_multiple_private_route_tables = false

#   private_subnet_tags = {
#     "kubernetes.io/role/internal-elb" = 1
#     # Tags subnets for Karpenter auto-discovery
#     # "karpenter.sh/discovery" = "${lower(var.client_name)}${local.region_short}-cluster01"
#   }

#   public_subnet_tags = {
#     "kubernetes.io/role/elb" = 1
#   }

#   tags = {
#     Terraform   = "true"
#     Environment = "${var.client_name}"
#   }
# }

# Internet Gateway

resource "aws_internet_gateway" "igw" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name = "${lower(var.client_name)}${local.region_short}-igw"
  }
}

# EIP for NAT Gateway

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${lower(var.client_name)}${local.region_short}-nat"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat.allocation_id
  subnet_id     = module.vpc.public_subnets[0]

  tags = {
    Name = "${lower(var.client_name)}${local.region_short}-ngw"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Routing table for private subnet
resource "aws_route_table" "private_rt" {
  vpc_id = module.vpc.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw.id
  }

  tags = {
    Name = "${lower(var.client_name)}${local.region_short}-private-rt"
  }
}

# Private route table association
resource "aws_route_table_association" "priv_ass" {
  for_each = {
    for i, subnet_id in module.vpc.private_subnets :
    i => subnet_id
  }

  subnet_id      = each.value
  route_table_id = aws_route_table.private_rt.id
}

# Routing table for public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = module.vpc.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${lower(var.client_name)}${local.region_short}-public-rt"
  }
}

# Public route table association
resource "aws_route_table_association" "pub_ass" {
  for_each = {
    for i, subnet_id in module.vpc.public_subnets :
    i => subnet_id
  }

  subnet_id      = each.value
  route_table_id = aws_route_table.public_rt.id
}