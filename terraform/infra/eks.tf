# -----------------------------------------------------------------------------
# eks.tf - the Kubernetes cluster (EKS) and its worker nodes.
# -----------------------------------------------------------------------------

# --- The cluster (control plane, run and managed by AWS) ---------------------
resource "aws_eks_cluster" "main" {
  name     = var.projectname
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    # The control plane's network interfaces go into the private subnets.
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.control_plane.id]

    # Nodes reach the API privately, inside the VPC.
    endpoint_private_access = true
    # kubectl on your laptop and the GitHub runners reach it over the internet.
    # Access is still protected by IAM: only the principals in the access
    # entries below can do anything in the cluster.
    endpoint_public_access = true
  }

  # Who can use kubectl is managed with "access entries" (below).
  # We list every admin explicitly instead of automatically making the creator
  # an admin - so it does not matter whether you or the pipeline creates the cluster.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# --- Cluster admins ----------------------------------------------------------
# The GitHub Actions role from terraform/bootstrap (looked up by name).
data "aws_iam_role" "github_actions" {
  name = "${var.projectname}-github-actions"
}

locals {
  cluster_admins = {
    you    = var.admin_principal_arn              # you, with kubectl
    github = data.aws_iam_role.github_actions.arn # the pipeline, with kubectl apply
  }
}

# An access entry maps an IAM user/role to permissions inside Kubernetes.
resource "aws_eks_access_entry" "admins" {
  for_each      = local.cluster_admins
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
}

resource "aws_eks_access_policy_association" "admins" {
  for_each      = local.cluster_admins
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster" # admin in the whole cluster
  }

  depends_on = [aws_eks_access_entry.admins]
}

# --- Worker nodes ------------------------------------------------------------
# A launch template lets us attach our own security group to the nodes.
# We also keep the security group EKS creates automatically for the cluster,
# because that is what EKS nodes get by default.
resource "aws_launch_template" "nodes" {
  name_prefix            = "${var.projectname}-nodes-"
  update_default_version = true

  vpc_security_group_ids = [
    aws_security_group.nodes.id,
    aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
  ]

  # Give the EC2 instances a readable name in the AWS console.
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.projectname}-node"
      Project = var.projectname
    }
  }
}

# A managed node group: EC2 instances that AWS creates, joins to the cluster
# and replaces if they become unhealthy.
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.projectname}-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = aws_subnet.private[*].id # nodes are private
  instance_types  = [var.node_instance_type]

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count
  }

  # Permissions and firewall rules must exist before nodes try to join.
  depends_on = [
    aws_iam_role_policy_attachment.nodes,
    aws_vpc_security_group_ingress_rule.control_plane_from_nodes,
    aws_vpc_security_group_ingress_rule.nodes_from_control_plane,
    aws_vpc_security_group_ingress_rule.nodes_from_nodes,
  ]
}
