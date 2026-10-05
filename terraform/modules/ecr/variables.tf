variable "namespace" {
  description = "Repository name prefix, e.g. cloudcart -> cloudcart/user-service."
  type        = string
  default     = "cloudcart"
}

variable "repositories" {
  description = "Service names; one repository is created for each."
  type        = list(string)
}

variable "max_image_count" {
  description = "Images kept per repository. Must cover the rollback window for every environment."
  type        = number
  default     = 50
}

variable "untagged_expiry_days" {
  description = "Days after which untagged images are deleted."
  type        = number
  default     = 7
}

variable "kms_key_arn" {
  description = "Customer managed KMS key for image encryption. null uses AES256."
  type        = string
  default     = null
}

variable "force_delete" {
  description = "Allow terraform destroy to delete repositories that still contain images."
  type        = bool
  default     = false
}
