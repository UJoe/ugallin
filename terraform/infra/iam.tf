# -----------------------------------------------------------------------------
# iam.tf - IAM roles = AWS permissions for the EKS cluster and the worker nodes.
#
# A role has two parts:
#   - a trust policy (assume_role_policy): WHO may use the role
#   - attached policies: WHAT the role may do
# -----------------------------------------------------------------------------

# --- 8a. Cluster role: used by the EKS service to manage the control plane ---
resource "aws_iam_role" "cluster" {
  name = "${var.projectname}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" } # only the EKS service
      Action    = "sts:AssumeRole"
    }]
  })
}

# AWS-managed policy with everything the EKS control plane needs.
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --- 8b. Node role: used by the EC2 worker nodes ------------------------------
resource "aws_iam_role" "nodes" {
  name = "${var.projectname}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" } # only EC2 instances
      Action    = "sts:AssumeRole"
    }]
  })
}

# The three AWS-managed policies every EKS worker node needs:
#   - AmazonEKSWorkerNodePolicy:          join the cluster
#   - AmazonEKS_CNI_Policy:               give pods IP addresses from the VPC
#   - AmazonEC2ContainerRegistryReadOnly: pull our image from ECR
resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.nodes.name
  policy_arn = each.value
}
