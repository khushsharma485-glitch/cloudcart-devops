# Offline tests for the CloudCart stack: run `terraform test` in terraform/.
#
# The AWS provider is mocked, so these tests need no credentials and create
# nothing. They check how the modules are wired together and the per-
# environment logic: AZ layout, NAT strategy, ECR ownership and the guard
# rails on the Kubernetes API endpoint. Module internals (RDS hardening,
# ECR settings) are covered by the tests inside each module.

mock_provider "aws" {
  # The mock provider generates random strings, which fail the AWS
  # provider's ARN/ID validation, so realistic defaults are supplied.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-west-1:123456789012:log-group:mock" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-west-1:123456789012:key/mock" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:eu-west-1:123456789012:mock" }
  }
  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:eu-west-1:123456789012:repository/cloudcart/mock"
      repository_url = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/cloudcart/mock"
      registry_id    = "123456789012"
    }
  }
  mock_resource "aws_eks_cluster" {
    defaults = { arn = "arn:aws:eks:eu-west-1:123456789012:cluster/mock" }
  }
  mock_resource "aws_db_instance" {
    defaults = { arn = "arn:aws:rds:eu-west-1:123456789012:db:mock" }
  }

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
  }
  override_data {
    target = module.vpc.data.aws_region.current
    values = { region = "eu-west-1" }
  }
  override_data {
    target = data.aws_region.current
    values = { region = "eu-west-1" }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }
  override_data {
    target = module.eks.data.aws_partition.current
    values = { partition = "aws" }
  }
  override_data {
    target = module.iam.data.aws_partition.current
    values = { partition = "aws" }
  }
  override_data {
    target = module.iam.data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }
  override_data {
    target = data.aws_ecr_repository.shared
    values = {
      arn            = "arn:aws:ecr:eu-west-1:123456789012:repository/cloudcart/shared"
      repository_url = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/cloudcart/shared"
    }
  }

  override_resource {
    target = module.eks.aws_eks_cluster.this
    values = {
      vpc_config            = { cluster_security_group_id = "sg-0cluster" }
      certificate_authority = [{ data = "LS0tLS1CRUdJTi0tLS0t" }]
    }
  }
  override_resource {
    target = module.eks.aws_launch_template.node
    values = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
  override_resource {
    target = module.rds.aws_db_instance.this
    values = {
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:rds!db-abc", kms_key_id = "k", secret_status = "active" }]
    }
  }
}

variables {
  github_repository         = "example/cloudcart-devops"
  eks_public_endpoint_cidrs = ["203.0.113.10/32"]
}

run "dev_is_cost_optimised" {
  command = apply

  variables {
    environment        = "dev"
    az_count           = 2
    single_nat_gateway = true
    create_ecr         = true
    node_capacity_type = "SPOT"
  }

  assert {
    condition     = length(module.vpc.private_subnet_ids) == 2 && length(module.vpc.database_subnet_ids) == 2
    error_message = "dev should span exactly two AZs"
  }

  assert {
    condition     = length(module.vpc.nat_public_ips) == 1
    error_message = "dev should use a single shared NAT gateway"
  }

  assert {
    condition     = length(module.ecr) == 1 && length(local.ecr_repository_arns) == 3
    error_message = "dev owns one ECR repository per service"
  }

  assert {
    condition     = output.rds_master_secret_arn == "arn:aws:secretsmanager:eu-west-1:123456789012:secret:rds!db-abc"
    error_message = "the RDS Secrets Manager ARN must be exported for External Secrets"
  }

  assert {
    condition     = output.kubeconfig_command == "aws eks update-kubeconfig --name cloudcart-dev --region eu-west-1"
    error_message = "kubeconfig helper output is wrong"
  }
}

run "prod_is_highly_available" {
  command = apply

  variables {
    environment                 = "prod"
    az_count                    = 3
    single_nat_gateway          = false
    create_ecr                  = false
    create_github_oidc_provider = false
    db_multi_az                 = true
    db_deletion_protection      = true
  }

  assert {
    condition     = length(module.vpc.private_subnet_ids) == 3
    error_message = "prod should span three AZs"
  }

  assert {
    condition     = length(module.vpc.nat_public_ips) == 3
    error_message = "prod needs one NAT gateway per AZ"
  }

  assert {
    condition     = length(module.ecr) == 0 && length(local.ecr_repository_arns) == 3
    error_message = "prod must reuse the shared ECR repositories, not create its own"
  }
}

run "api_endpoint_cannot_be_open_to_the_internet" {
  command = plan

  variables {
    environment               = "dev"
    create_ecr                = true
    eks_public_endpoint_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.eks_public_endpoint_cidrs]
}

run "public_endpoint_requires_an_allow_list" {
  command = plan

  variables {
    environment               = "dev"
    create_ecr                = true
    eks_public_endpoint_cidrs = []
  }

  expect_failures = [var.eks_public_endpoint_cidrs]
}
