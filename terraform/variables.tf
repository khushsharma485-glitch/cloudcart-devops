variable "environment" {
  description = "Environment name (dev or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "The environment value must be dev or prod."
  }
}

variable "services" {
  description = "CloudCart microservices (one ECR repository each)."
  type        = list(string)
  default     = ["user-service", "product-service", "order-service"]
}

variable "github_repository" {
  description = "owner/repo of this repository, trusted for OIDC."
  type        = string
}

variable "create_github_oidc_provider" {
  type    = bool
  default = true
}

variable "create_ecr" {
  description = "Create the shared ECR repositories in this environment (exactly one environment should)."
  type        = bool
  default     = false
}

# --- Network ---

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

# --- EKS ---

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "eks_public_endpoint" {
  type    = bool
  default = true
}

variable "eks_public_endpoint_cidrs" {
  description = "Operator CIDRs allowed to reach the public Kubernetes API endpoint."
  type        = list(string)
  default     = []

  validation {
    # An empty list would make AWS fall back to 0.0.0.0/0.
    condition     = !var.eks_public_endpoint || (length(var.eks_public_endpoint_cidrs) > 0 && !contains(var.eks_public_endpoint_cidrs, "0.0.0.0/0"))
    error_message = "With a public EKS endpoint, list at least one operator CIDR and never 0.0.0.0/0."
  }
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
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

variable "eks_access_entries" {
  description = "Human/automation IAM principals and their EKS access policy. See modules/eks."
  type = map(object({
    principal_arn     = string
    policy            = optional(string)
    namespaces        = optional(list(string), [])
    kubernetes_groups = optional(list(string), [])
  }))
  default = {}
}

# --- RDS ---

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 20
}

variable "db_max_allocated_storage_gb" {
  type    = number
  default = 50
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "db_deletion_protection" {
  type    = bool
  default = true
}

# --- Alerting ---

variable "alert_emails" {
  description = "Addresses subscribed to the alerts SNS topic (each must confirm by email)."
  type        = list(string)
  default     = []
}
