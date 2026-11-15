# -----------------------------------------------------------------------------
# BOOTSTRAP - apply this folder ONCE, by hand, before the first pipeline run.
#
# It creates the two things the pipeline needs before it can run Terraform:
#   1. an S3 bucket that stores the Terraform state of terraform/infra
#      (the GitHub runner starts empty every time, so the state must be shared)
#   2. an IAM role that GitHub Actions logs in to with OIDC (no AWS keys stored)
#
# This folder keeps its own state locally (terraform.tfstate here) - do not
# delete that file until you have destroyed everything (see README).
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Added to every resource: who owns it and which project it belongs to.
  default_tags {
    tags = {
      Project   = var.projectname
      ManagedBy = "terraform"
    }
  }
}

# The AWS account ID, used to make the bucket name globally unique.
data "aws_caller_identity" "current" {}

# --- 1. S3 bucket for the Terraform state ------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.projectname}-tfstate-${data.aws_caller_identity.current.account_id}"

  # Allows `terraform destroy` to delete the bucket even if it still has files.
  force_destroy = true
}

# Keep old versions of the state file, so a broken state can be restored.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# The state must never be public.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- 2. IAM role for GitHub Actions ------------------------------------------
# GitHub's OIDC identity provider already exists in the account (only one is
# allowed per account), so we look it up instead of creating it.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name = "${var.projectname}-github-actions"

  # Trust policy: WHO may use this role. Only GitHub Actions workflows of our
  # own repository - on any branch or pull request ("*" at the end).
  # GitHub sends the repo either as "owner/repo" or, in its newer format, with
  # numeric IDs as "owner@123/repo@456", so both forms are allowed.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_owner}/${var.github_repo}:*",
            "repo:${var.github_owner}@*/${var.github_repo}@*:*",
          ]
        }
      }
    }]
  })
}

# Permissions: WHAT the role may do. The pipeline creates a VPC, an EKS cluster,
# IAM roles, a load balancer and an ECR repository, which needs very broad
# rights - so, to keep it simple, we give it AdministratorAccess.
# This is acceptable for a learning project because only our own repository can
# use the role (see the trust policy above). In a real company you would give
# only the permissions that are actually needed.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
