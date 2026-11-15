# -----------------------------------------------------------------------------
# loadbalancer.tf - makes the app reachable from the internet (step 12).
#
#   http://<NLB DNS name>:80  -->  every worker node, port 30080 (NodePort)
#                             -->  Kubernetes forwards to an app pod, port 8080
#
# We create the load balancer with Terraform. Kubernetes only opens the same
# port (30080) on every node (Service type NodePort in k8s/app.yaml), so no
# extra load balancer controller is needed in the cluster.
# -----------------------------------------------------------------------------

# A Network Load Balancer in the public subnets, reachable from the internet.
resource "aws_lb" "app" {
  name               = "${var.projectname}-nlb"
  load_balancer_type = "network"
  internal           = false
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.nlb.id]

  # Spread requests evenly over the nodes in both AZs.
  enable_cross_zone_load_balancing = true
}

# The target group = where the NLB sends traffic: the worker nodes, on the NodePort.
resource "aws_lb_target_group" "app" {
  name        = "${var.projectname}-tg"
  port        = var.node_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  # Only healthy nodes get traffic. "traffic-port" = the NodePort (30080).
  health_check {
    protocol = "HTTP"
    path     = "/healthz"
    port     = "traffic-port"
  }

  # Wait only 30s (instead of 300s) before removing a node that is going away.
  deregistration_delay = 30
}

# Listen on port 80 and forward everything to the target group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Register the worker nodes in the target group automatically: the node group's
# Auto Scaling Group adds every new node (and removes old ones) by itself.
resource "aws_autoscaling_attachment" "nodes" {
  autoscaling_group_name = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.app.arn
}
