variable "name" {
  description = "Name prefix for IAM roles."
  type        = string
}

variable "cluster_name" {
  type = string
}

variable "github_repository" {
  description = "owner/repo allowed to assume the CI role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "The github_repository value must look like owner/repo."
  }
}

variable "github_allowed_refs" {
  description = "Git refs whose workflows may assume the CI role. Pull requests are deliberately excluded."
  type        = list(string)
  default     = ["refs/heads/main", "refs/tags/v*"]
}

variable "create_github_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider (only once per account)."
  type        = bool
  default     = true
}

variable "ecr_repository_arns" {
  description = "Repositories the CI role may push to."
  type        = list(string)
}

variable "readable_secret_arns" {
  description = "Secrets Manager ARNs External Secrets may read."
  type        = list(string)
}
