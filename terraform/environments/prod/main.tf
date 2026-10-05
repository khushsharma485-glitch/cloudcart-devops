# PROD - optimised for availability. Three AZs, a NAT gateway per AZ,
# on-demand nodes, Multi-AZ RDS with deletion protection and longer backups.
# Uses the ECR repositories created by dev: the exact image tested in dev
# is the one promoted to prod.

module "cloudcart" {
  source = "../.."

  environment       = "prod"
  github_repository = var.github_repository

  create_ecr                  = false
  create_github_oidc_provider = false # already created by dev in this account

  vpc_cidr           = "10.20.0.0/16"
  az_count           = 3
  single_nat_gateway = false

  kubernetes_version        = "1.36"
  eks_public_endpoint       = true
  eks_public_endpoint_cidrs = var.eks_public_endpoint_cidrs
  node_instance_types       = ["m6i.large"]
  node_capacity_type        = "ON_DEMAND"
  node_min_size             = 3
  node_desired_size         = 3
  node_max_size             = 9
  eks_access_entries        = var.eks_access_entries

  db_instance_class           = "db.t4g.medium"
  db_allocated_storage_gb     = 50
  db_max_allocated_storage_gb = 200
  db_multi_az                 = true
  db_backup_retention_days    = 14
  db_deletion_protection      = true

  alert_emails = var.alert_emails
}
