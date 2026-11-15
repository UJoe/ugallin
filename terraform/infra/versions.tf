# -----------------------------------------------------------------------------
# versions.tf - Terraform/provider versions, where the state is stored, and
# how to connect to AWS.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10.0" # 1.10+ is needed for S3 state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The state (Terraform's record of what it created) lives in the S3 bucket
  # created by terraform/bootstrap, so your laptop and the GitHub pipeline both
  # see the same state. use_lockfile stops two runs from changing things at
  # the same time.
  # Backend settings cannot use variables, so the values are written out here.
  # If you change projectname or the AWS account, change the bucket name too.
  backend "s3" {
    bucket       = "ugallin-tfstate-362099375729"
    key          = "infra/terraform.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # These tags are added to EVERY resource, so it is easy to see in the
  # (shared) AWS account what belongs to this project.
  default_tags {
    tags = {
      Project   = var.projectname
      ManagedBy = "terraform"
    }
  }
}
