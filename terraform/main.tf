# CloudCart infrastructure stack.
#
# This root module composes the reusable modules into one environment. It
# has no backend or provider configuration of its own. Each directory in
# environments/ (dev, prod) calls it with environment-specific sizing and
# its own remote state, so the two environments can never share state.
#
#   environments/dev  ─┐
#                      ├──► terraform/ (this stack) ──► modules/{vpc,eks,rds,ecr,iam}
#   environments/prod ─┘

locals {
  name         = "cloudcart-${var.environment}"
  cluster_name = "cloudcart-${var.environment}"
}

module "vpc" {
  source = "./modules/vpc"

  name               = local.name
  cluster_name       = local.cluster_name
  cidr_block         = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
}

module "ecr" {
  source = "./modules/ecr"

  # ECR repositories are shared by all environments: the same immutable
  # image is promoted from dev to prod. Only the environment that owns
  # them (create_ecr = true) creates them.
  count = var.create_ecr ? 1 : 0

  repositories    = var.services
  max_image_count = 100
}

module "eks" {
  source = "./modules/eks"

  cluster_name                 = local.cluster_name
  kubernetes_version           = var.kubernetes_version
  private_subnet_ids           = module.vpc.private_subnet_ids
  endpoint_public_access       = var.eks_public_endpoint
  endpoint_public_access_cidrs = var.eks_public_endpoint_cidrs

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size

  access_entries = var.eks_access_entries
}

module "rds" {
  source = "./modules/rds"

  identifier              = local.name
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.database_subnet_ids
  allowed_security_groups = { eks-cluster = module.eks.cluster_security_group_id }

  instance_class           = var.db_instance_class
  allocated_storage_gb     = var.db_allocated_storage_gb
  max_allocated_storage_gb = var.db_max_allocated_storage_gb
  multi_az                 = var.db_multi_az
  backup_retention_days    = var.db_backup_retention_days
  deletion_protection      = var.db_deletion_protection
  skip_final_snapshot      = !var.db_deletion_protection

  alarm_sns_topic_arn = aws_sns_topic.alerts.arn
}

data "aws_ecr_repository" "shared" {
  for_each = var.create_ecr ? toset([]) : toset(var.services)
  name     = "cloudcart/${each.value}"
}

locals {
  ecr_repository_arns = var.create_ecr ? values(module.ecr[0].repository_arns) : [for r in data.aws_ecr_repository.shared : r.arn]
  ecr_repository_urls = var.create_ecr ? module.ecr[0].repository_urls : { for k, r in data.aws_ecr_repository.shared : k => r.repository_url }
}

module "iam" {
  source = "./modules/iam"

  name                        = local.name
  cluster_name                = module.eks.cluster_name
  github_repository           = var.github_repository
  create_github_oidc_provider = var.create_github_oidc_provider
  ecr_repository_arns         = local.ecr_repository_arns
  readable_secret_arns = [
    module.rds.master_user_secret_arn,
    # Platform credentials (Grafana admin, Alertmanager Slack webhook).
    "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:cloudcart/${var.environment}/*",
  ]
}

# Note: the CI role has no Kubernetes access at all. Deployments are pulled
# by Argo CD from Git, and rollout verification and automatic rollback run
# inside the cluster (Argo Rollouts analysis). CI only builds and publishes.

# --- Alert routing (CloudWatch alarms and Alertmanager both publish here) --

data "aws_caller_identity" "current" {}

# A customer managed key is required: CloudWatch alarms cannot publish to a
# topic encrypted with the AWS managed aws/sns key, because that key policy
# cannot grant cloudwatch.amazonaws.com access.
resource "aws_kms_key" "alerts" {
  description             = "${local.name} alerts SNS topic"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchAlarmsToPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
      },
    ]
  })
}

resource "aws_sns_topic" "alerts" {
  name              = "${local.name}-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudWatchAlarms"
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts.arn
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}
