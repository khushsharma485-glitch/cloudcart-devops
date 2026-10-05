# Provider requirements for the CloudCart stack.
#
# Provider *configuration* (region, credentials, default tags) and the state
# backend live in environments/<env>/, because a reusable root module must
# not hard-code them. Credentials always come from the environment
# (AWS SSO / aws-vault / OIDC in CI). They are never written in a .tf file.

terraform {
  required_version = ">= 1.10" # S3 native state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
