output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  value = aws_subnet.database[*].id
}

output "availability_zones" {
  value = local.azs
}

output "nat_public_ips" {
  description = "Egress IPs of the cluster, useful for third-party allow-lists."
  value       = aws_eip.nat[*].public_ip
}
