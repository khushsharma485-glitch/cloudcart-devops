# IAM for CloudCart. No long-lived access keys are created anywhere.
#
# 1. GitHub Actions -> AWS via OIDC federation. The CI role can only push to
#    the CloudCart ECR repositories (no cluster access), and only
#    workflows on the main branch or version tags can assume it.
# 2. Kubernetes controllers -> AWS via EKS Pod Identity. Each role is bound
#    to a single namespace/service account.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id

  github_oidc_url = "token.actions.githubusercontent.com"
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : (
    "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.github_oidc_url}"
  )

  pod_identity_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# --- GitHub Actions OIDC ---------------------------------------------------

# One per AWS account. If dev and prod share an account, create it in one
# environment only and set create_github_oidc_provider = false in the other.
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://${local.github_oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_ci" {
  name        = "${var.name}-github-ci"
  description = "Assumed by GitHub Actions in ${var.github_repository} to publish images"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.github_oidc_url}:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "${local.github_oidc_url}:sub" = [for ref in var.github_allowed_refs : "repo:${var.github_repository}:ref:${ref}"]
        }
      }
    }]
  })

  max_session_duration = 3600
}

resource "aws_iam_role_policy" "github_ci" {
  name = "ecr-push-only"
  role = aws_iam_role.github_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # this API does not support resource-level permissions
      },
      {
        Sid    = "EcrPushCloudCartOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = var.ecr_repository_arns
      }
    ]
  })
}

# --- AWS Load Balancer Controller (creates the ALB for the Ingress) -------

resource "aws_iam_role" "lb_controller" {
  name               = "${var.name}-aws-lb-controller"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_policy" "lb_controller" {
  name        = "${var.name}-aws-lb-controller"
  description = "Upstream policy from kubernetes-sigs/aws-load-balancer-controller"
  policy      = file("${path.module}/policies/aws-load-balancer-controller.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn
}

# --- External Secrets Operator (Secrets Manager -> Kubernetes Secret) -----

resource "aws_iam_role" "external_secrets" {
  name               = "${var.name}-external-secrets"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "read-cloudcart-secrets"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadOnlyTheSecretsCloudCartNeeds"
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      Resource = var.readable_secret_arns
    }]
  })
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn
}
