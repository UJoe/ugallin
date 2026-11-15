variable "projectname" {
  description = "Project name. Every resource name starts with it."
  type        = string
  default     = "ugallin"
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-central-1"
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repository."
  type        = string
  default     = "UJoe"
}

variable "github_repo" {
  description = "Name of the GitHub repository that contains this project."
  type        = string
  default     = "ugallin"
}
