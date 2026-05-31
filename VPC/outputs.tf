# Output
output "vpc_id" {
  value = module.vpc.vpc_id
}


output "private_zone1_subnet_id" {
  value = aws_subnet.private_zone1.id
}

output "private_zone2_subnet_id" {
  value = aws_subnet.private_zone2.id
}