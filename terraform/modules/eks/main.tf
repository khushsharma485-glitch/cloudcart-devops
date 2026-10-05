# EKS cluster + managed node group.
#
# Security posture:
# - Nodes run in private subnets only.
# - Kubernetes Secrets are envelope-encrypted with a customer managed KMS key.
# - Control plane audit/api/authenticator logs go to CloudWatch.
# - Access is granted with EKS access entries (IAM -> Kubernetes), not the
#   legacy aws-auth ConfigMap.
# - Workloads get AWS permissions through EKS Pod Identity, never node roles.

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition
}

# --- KMS key for Kubernetes Secrets encryption ----------------------------

resource "aws_kms_key" "secrets" {
  description             = "EKS ${var.cluster_name} secrets envelope encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/eks/${var.cluster_name}"
  target_key_id = aws_kms_key.secrets.key_id
}

# --- Control plane ---------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Created before the cluster so retention is under our control
# (EKS would otherwise create it with "never expire").
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.secrets.arn
    }
  }

  upgrade_policy {
    support_type = var.upgrade_support_type
  }

  lifecycle {
    precondition {
      # An empty list would make AWS fall back to 0.0.0.0/0.
      condition     = !var.endpoint_public_access || length(var.endpoint_public_access_cidrs) > 0
      error_message = "endpoint_public_access is true, so endpoint_public_access_cidrs must list at least one operator CIDR."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

# --- Worker nodes ----------------------------------------------------------

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly", # this is how nodes pull images from ECR
    "AmazonSSMManagedInstanceCore",       # shell access via SSM, no SSH keys or port 22
  ])
  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

resource "aws_launch_template" "node" {
  name_prefix = "${var.cluster_name}-node-"

  # IMDSv2 only, hop limit 1: pods cannot reach the node's instance metadata
  # and borrow the node role. Pod Identity is used instead.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.cluster_name}-node" }
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "cloudcart.io/node-pool" = "default"
  }

  # desired_size is changed at runtime by autoscaling; do not fight it.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# --- Managed add-ons -------------------------------------------------------

resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "this" {
  for_each = {
    "vpc-cni"                = { before_nodes = true }
    "eks-pod-identity-agent" = { before_nodes = true }
    "kube-proxy"             = { before_nodes = true }
    "coredns"                = { before_nodes = false }
    "aws-ebs-csi-driver"     = { before_nodes = false } # PVCs for Prometheus / Loki
    "metrics-server"         = { before_nodes = false } # required by HPA
  }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  # The VPC CNI only enforces Kubernetes NetworkPolicies when this is on.
  # Without it, NetworkPolicy objects are accepted but silently ignored.
  configuration_values = each.key == "vpc-cni" ? jsonencode({ enableNetworkPolicy = "true" }) : null

  dynamic "pod_identity_association" {
    for_each = each.key == "aws-ebs-csi-driver" ? [1] : []
    content {
      role_arn        = aws_iam_role.ebs_csi.arn
      service_account = "ebs-csi-controller-sa"
    }
  }

  depends_on = [aws_eks_node_group.default]
}

# --- Access entries (IAM principal -> Kubernetes permissions) -------------

resource "aws_eks_access_entry" "this" {
  for_each      = var.access_entries
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"

  # Groups are bound to namespaced Roles in kubernetes/rbac (fine-grained),
  # as an alternative to the coarse EKS access policies below.
  kubernetes_groups = each.value.kubernetes_groups
}

resource "aws_eks_access_policy_association" "this" {
  for_each      = { for k, v in var.access_entries : k => v if v.policy != null }
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/${each.value.policy}"

  access_scope {
    type       = length(each.value.namespaces) > 0 ? "namespace" : "cluster"
    namespaces = length(each.value.namespaces) > 0 ? each.value.namespaces : null
  }

  depends_on = [aws_eks_access_entry.this]
}
