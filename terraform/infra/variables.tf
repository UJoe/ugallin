# -----------------------------------------------------------------------------
# variables.tf - the settings of this project. Change values here (or in a
# terraform.tfvars file) instead of editing the other files.
# -----------------------------------------------------------------------------

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

variable "vpc_cidr" {
  description = "IP address range of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Kubernetes version of the EKS cluster. Use a version in standard support (extended support costs ~6x more)."
  type        = string
  default     = "1.37"
}

variable "node_instance_type" {
  description = "EC2 instance type of the worker nodes."
  type        = string
  default     = "t3.small"
}

variable "node_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}

variable "node_port" {
  description = "Port the Kubernetes NodePort Service listens on, on every node. Must match nodePort in k8s/app.yaml."
  type        = number
  default     = 30080
}

variable "admin_principal_arn" {
  description = "IAM user/role that gets admin access to the cluster, so you can use kubectl. Get yours with: aws sts get-caller-identity --query Arn --output text"
  type        = string
  # No default on purpose - it differs per person. The pipeline gets it from
  # the GitHub variable ADMIN_PRINCIPAL_ARN; locally use:
  #   export TF_VAR_admin_principal_arn=$(aws sts get-caller-identity --query Arn --output text)

  # Stop right away with a clear message if it is empty or not an IAM ARN
  # (e.g. the GitHub variable is missing - then the value is an empty string).
  validation {
    condition     = startswith(var.admin_principal_arn, "arn:aws:iam::")
    error_message = "admin_principal_arn must be an IAM ARN, e.g. arn:aws:iam::123456789012:user/me. Set the GitHub variable ADMIN_PRINCIPAL_ARN or export TF_VAR_admin_principal_arn."
  }
}
