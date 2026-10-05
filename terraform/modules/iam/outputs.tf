output "github_ci_role_arn" {
  description = "Set as the AWS_CI_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.github_ci.arn
}

output "lb_controller_role_arn" {
  value = aws_iam_role.lb_controller.arn
}

output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}
