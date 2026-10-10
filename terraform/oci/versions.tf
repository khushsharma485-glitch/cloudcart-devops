terraform {
  required_version = ">= 1.10"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.9"
    }
  }

  # State stays local for the free setup (terraform.tfstate is git-ignored).
  # For a team, move it to an OCI Object Storage bucket (S3-compatible backend,
  # which is also inside the Always Free 20 GB).
}

# Authentication comes from ~/.oci/config (created when you add an API key in
# the OCI console). No keys or OCIDs are written in this repository.
provider "oci" {
  config_file_profile = var.oci_profile
  region              = var.region
}
