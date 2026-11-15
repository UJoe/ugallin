# -----------------------------------------------------------------------------
# security.tf - security groups (firewalls around individual resources).
#
# Security groups are STATEFUL: if a request is allowed in, its reply is
# allowed out automatically (unlike the NACLs in network.tf).
#
#   Internet --80--> [nlb SG] --30080--> [nodes SG] <--443/10250--> [control plane SG]
# -----------------------------------------------------------------------------

# --- 7a. Control plane security group ----------------------------------------
# Attached to the EKS control plane's network interfaces in our subnets.
resource "aws_security_group" "control_plane" {
  name        = "${var.projectname}-control-plane-sg"
  description = "EKS control plane"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outgoing traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.projectname}-control-plane-sg" }
}

# --- 7b. Worker node security group ------------------------------------------
resource "aws_security_group" "nodes" {
  name        = "${var.projectname}-nodes-sg"
  description = "EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outgoing traffic (control plane, image pulls via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.projectname}-nodes-sg" }
}

# --- Load balancer security group --------------------------------------------
resource "aws_security_group" "nlb" {
  name        = "${var.projectname}-nlb-sg"
  description = "Public load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward traffic to the worker nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.projectname}-nlb-sg" }
}

# --- Rules between the groups ------------------------------------------------
# Separate rule resources (instead of inline blocks) are needed because the
# groups refer to each other.

# Nodes -> control plane: the kubelet on each node talks to the Kubernetes API (HTTPS).
resource "aws_vpc_security_group_ingress_rule" "control_plane_from_nodes" {
  security_group_id            = aws_security_group.control_plane.id
  referenced_security_group_id = aws_security_group.nodes.id
  description                  = "Kubernetes API from worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# Control plane -> nodes: kubelet API (logs, exec) and webhooks running in pods.
resource "aws_vpc_security_group_ingress_rule" "nodes_from_control_plane" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.control_plane.id
  description                  = "Control plane to kubelet and pods"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 65535
}

# Node <-> node: pods on different nodes talk to each other (e.g. DNS via CoreDNS).
resource "aws_vpc_security_group_ingress_rule" "nodes_from_nodes" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  description                  = "All traffic between worker nodes"
  ip_protocol                  = "-1"
}

# Load balancer -> nodes: user requests to the app's NodePort.
resource "aws_vpc_security_group_ingress_rule" "nodes_from_nlb" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nlb.id
  description                  = "App NodePort from the load balancer"
  ip_protocol                  = "tcp"
  from_port                    = var.node_port
  to_port                      = var.node_port
}
