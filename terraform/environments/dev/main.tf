# DEV - optimised for cost. Single NAT gateway, spot nodes, single-AZ RDS,
# no deletion protection. It owns the shared ECR repositories and the
# account-wide GitHub OIDC provider.

module "cloudcart" {
  source = "../.."

  environment       = "dev"
  github_repository = var.github_repository

  create_ecr                  = true
  create_github_oidc_provider = true

  vpc_cidr           = "10.10.0.0/16"
  az_count           = 2
  single_nat_gateway = true

  kubernetes_version        = "1.36"
  eks_public_endpoint       = true
  eks_public_endpoint_cidrs = var.eks_public_endpoint_cidrs
  node_instance_types       = ["t3.medium", "t3a.medium"]
  node_capacity_type        = "SPOT"
  node_min_size             = 2
  node_desired_size         = 2
  node_max_size             = 4
  eks_access_entries        = var.eks_access_entries

  db_instance_class           = "db.t4g.micro"
  db_allocated_storage_gb     = 20
  db_max_allocated_storage_gb = 50
  db_multi_az                 = false
  db_backup_retention_days    = 3
  db_deletion_protection      = false

  alert_emails = var.alert_emails
}
