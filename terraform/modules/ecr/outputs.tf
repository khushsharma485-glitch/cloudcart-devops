output "repository_urls" {
  description = "Map of service name to repository URL."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "Map of service name to repository ARN."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

output "registry_id" {
  value = one(distinct([for r in aws_ecr_repository.this : r.registry_id]))
}
