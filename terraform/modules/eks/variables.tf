variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
  default     = "1.36"
}

variable "upgrade_support_type" {
  description = "STANDARD avoids paid extended support. Upgrade before end of standard support."
  type        = string
  default     = "STANDARD"
}

variable "private_subnet_ids" {
  description = "Subnets for the control plane ENIs and worker nodes."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API publicly, limited to endpoint_public_access_cidrs. false means private only (VPN/SSM needed)."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "Operator CIDRs allowed to reach the public API endpoint. Never 0.0.0.0/0."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "Do not expose the Kubernetes API to the whole Internet; list operator CIDRs instead."
  }
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "The node_capacity_type value must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_disk_size_gb" {
  type    = number
  default = 40
}

variable "log_retention_days" {
  description = "CloudWatch retention for control plane logs."
  type        = number
  default     = 30
}

variable "access_entries" {
  description = <<-EOT
    IAM principals that may use the cluster. policy is an EKS access policy name
    (AmazonEKSClusterAdminPolicy, AmazonEKSAdminPolicy, AmazonEKSEditPolicy,
    AmazonEKSViewPolicy), or null when access comes only from kubernetes_groups
    bound by Kubernetes RBAC. Empty namespaces means cluster-wide.
  EOT
  type = map(object({
    principal_arn     = string
    policy            = optional(string)
    namespaces        = optional(list(string), [])
    kubernetes_groups = optional(list(string), [])
  }))
  default = {}
}
