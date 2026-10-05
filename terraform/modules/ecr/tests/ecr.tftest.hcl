# Offline tests for the ECR module (mocked AWS provider, nothing is created).

mock_provider "aws" {
  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:eu-west-1:123456789012:repository/cloudcart/mock"
      registry_id    = "123456789012"
      repository_url = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/cloudcart/mock"
    }
  }
}

variables {
  repositories = ["user-service", "product-service", "order-service"]
}

run "one_immutable_scanned_repository_per_service" {
  command = apply

  assert {
    condition     = toset(keys(aws_ecr_repository.this)) == toset(["user-service", "product-service", "order-service"])
    error_message = "Expected one repository per service"
  }

  assert {
    condition     = aws_ecr_repository.this["order-service"].name == "cloudcart/order-service"
    error_message = "Repositories must be namespaced as cloudcart/<service>"
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_tag_mutability == "IMMUTABLE"])
    error_message = "Tags must be immutable so a deployed tag always means the same image"
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_scanning_configuration[0].scan_on_push])
    error_message = "Images must be scanned on push"
  }

  assert {
    condition     = alltrue([for p in aws_ecr_lifecycle_policy.this : length(jsondecode(p.policy).rules) == 2])
    error_message = "Every repository needs the cleanup lifecycle policy"
  }
}
