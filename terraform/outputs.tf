output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${data.aws_region.current.region}"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "ecr_repository_urls" {
  value = local.ecr_repository_urls
}

output "rds_address" {
  description = "Goes into the Helm values as database.host."
  value       = module.rds.address
}

output "rds_master_secret_arn" {
  description = "Goes into the Helm values as database.secretsManagerKey (the External Secrets remote key)."
  value       = module.rds.master_user_secret_arn
}

output "github_actions_role_arn" {
  description = "Set as the AWS_CI_ROLE_ARN variable in GitHub repository settings."
  value       = module.iam.github_ci_role_arn
}

output "alerts_sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "nat_public_ips" {
  value = module.vpc.nat_public_ips
}

data "aws_region" "current" {}
