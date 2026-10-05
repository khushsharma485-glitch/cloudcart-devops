output "cluster_name" {
  value = module.cloudcart.cluster_name
}

output "kubeconfig_command" {
  value = module.cloudcart.kubeconfig_command
}

output "ecr_repository_urls" {
  value = module.cloudcart.ecr_repository_urls
}

output "rds_address" {
  value = module.cloudcart.rds_address
}

output "rds_master_secret_arn" {
  value = module.cloudcart.rds_master_secret_arn
}

output "github_actions_role_arn" {
  value = module.cloudcart.github_actions_role_arn
}

output "alerts_sns_topic_arn" {
  value = module.cloudcart.alerts_sns_topic_arn
}
