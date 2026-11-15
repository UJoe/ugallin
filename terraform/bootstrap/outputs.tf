output "tfstate_bucket" {
  description = "S3 bucket for the infra state. Must match the bucket in terraform/infra/versions.tf."
  value       = aws_s3_bucket.tfstate.bucket
}

output "github_actions_role_arn" {
  description = "Save this as the GitHub secret AWS_ROLE_ARN."
  value       = aws_iam_role.github_actions.arn
}
