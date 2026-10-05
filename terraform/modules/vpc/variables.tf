variable "name" {
  description = "Name prefix for all VPC resources."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name, used for subnet discovery tags."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR. Must be a /16 so the /20 subnet layout fits."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && endswith(var.cidr_block, "/16")
    error_message = "The cidr_block value must be a valid /16 CIDR."
  }
}

variable "az_count" {
  description = "Number of availability zones (2-4). RDS and EKS need at least 2."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "The az_count value must be between 2 and 4."
  }
}

variable "single_nat_gateway" {
  description = "true: one shared NAT gateway (cheap, dev). false: one per AZ (HA, prod)."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Send rejected-traffic VPC flow logs to CloudWatch."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs."
  type        = number
  default     = 14
}
