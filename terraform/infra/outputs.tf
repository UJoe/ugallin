# -----------------------------------------------------------------------------
# outputs.tf - useful values, printed after `terraform apply`
# (and any time with `terraform output`).
# -----------------------------------------------------------------------------

output "app_url" {
  description = "Open this in the browser (the NLB needs 1-3 minutes after creation to become healthy)."
  value       = "http://${aws_lb.app.dns_name}"
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "kubeconfig_command" {
  description = "Run this to connect kubectl to the cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "ecr_repository_url" {
  description = "Where the app image is pushed."
  value       = aws_ecr_repository.app.repository_url
}
