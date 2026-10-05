terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration: bucket and region are supplied at init time so no
  # account-specific values are committed:
  #   terraform init -backend-config=backend.hcl
  # See backend.hcl.example. State locking uses S3 native lock files.
  backend "s3" {
    key          = "cloudcart/prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # Credentials are taken from the standard AWS chain (SSO, env vars,
  # instance/OIDC role). Never put access keys here.

  default_tags {
    tags = {
      Project     = "cloudcart"
      Environment = "prod"
      ManagedBy   = "terraform"
      Repository  = var.github_repository
    }
  }
}
