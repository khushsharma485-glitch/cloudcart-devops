variable "oci_profile" {
  description = "Profile name in ~/.oci/config."
  type        = string
  default     = "DEFAULT"
}

variable "region" {
  description = "Your OCI home region (Always Free resources exist only there), e.g. ap-mumbai-1."
  type        = string
}

variable "tenancy_ocid" {
  description = "Tenancy OCID (the 'tenancy' line in ~/.oci/config)."
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment for the resources. Empty = the tenancy root compartment."
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Public key installed on the server for the ubuntu user."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "operator_cidrs" {
  description = "Your public IP(s) allowed to SSH to the server, e.g. [\"203.0.113.10/32\"]."
  type        = list(string)

  validation {
    condition     = length(var.operator_cidrs) > 0 && !contains(var.operator_cidrs, "0.0.0.0/0")
    error_message = "List at least one operator CIDR, and never 0.0.0.0/0 for SSH."
  }
}

variable "availability_domain_index" {
  description = "Which availability domain to use (0-based). If A1 capacity is unavailable in one, try another."
  type        = number
  default     = 0
}

# --- Always Free guard rails -------------------------------------------------
# Oracle's Always Free Ampere A1 allowance (since 2026-06-15) is 2 OCPUs and
# 12 GB in total, and 200 GB of block storage including boot volumes. The
# validations make it impossible to size this outside the free tier.

variable "ocpus" {
  type    = number
  default = 2

  validation {
    condition     = var.ocpus >= 1 && var.ocpus <= 2
    error_message = "Always Free allows at most 2 Ampere A1 OCPUs."
  }
}

variable "memory_gb" {
  type    = number
  default = 12

  validation {
    condition     = var.memory_gb >= 6 && var.memory_gb <= 12
    error_message = "Always Free allows at most 12 GB of Ampere A1 memory (k3s + CloudCart needs at least 6)."
  }
}

variable "boot_volume_gb" {
  type    = number
  default = 100

  validation {
    condition     = var.boot_volume_gb >= 50 && var.boot_volume_gb <= 200
    error_message = "Always Free block storage is 200 GB in total; keep the boot volume between 50 and 200 GB."
  }
}

variable "k3s_version" {
  description = "k3s release (https://github.com/k3s-io/k3s/releases)."
  type        = string
  default     = "v1.36.5+k3s1"
}
