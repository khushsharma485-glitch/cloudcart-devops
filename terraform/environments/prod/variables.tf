variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "github_repository" {
  description = "owner/repo of the CloudCart repository."
  type        = string
}

variable "eks_public_endpoint_cidrs" {
  description = "Operator IPs allowed to reach the Kubernetes API, for example [\"203.0.113.10/32\"]. Required."
  type        = list(string)

  validation {
    condition     = length(var.eks_public_endpoint_cidrs) > 0 && !contains(var.eks_public_endpoint_cidrs, "0.0.0.0/0")
    error_message = "List at least one operator CIDR, and never 0.0.0.0/0."
  }
}

variable "eks_access_entries" {
  description = "Extra IAM principals with cluster access (e.g. a developers role with AmazonEKSViewPolicy)."
  type = map(object({
    principal_arn     = string
    policy            = optional(string)
    namespaces        = optional(list(string), [])
    kubernetes_groups = optional(list(string), [])
  }))
  default = {}
}

variable "alert_emails" {
  type    = list(string)
  default = []
}
