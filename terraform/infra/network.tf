# -----------------------------------------------------------------------------
# network.tf - the network everything else lives in.
#
#                         Internet
#                            |
#                    Internet Gateway
#                            |
#   +----------------------- VPC 10.0.0.0/16 ------------------------+
#   |  public subnet AZ-a           |  public subnet AZ-b            |
#   |  (NLB, NAT Gateway)           |  (NLB)                         |
#   |-------------------------------|--------------------------------|
#   |  private subnet AZ-a          |  private subnet AZ-b           |
#   |  (EKS worker nodes)           |  (EKS worker nodes)            |
#   +----------------------------------------------------------------+
#
# Public subnets can be reached from the internet; private subnets cannot.
# The worker nodes are private: users reach them only through the load
# balancer, and they reach the internet (e.g. to pull images) through NAT.
# -----------------------------------------------------------------------------

# Ask AWS which availability zones (separate data centers) the region has,
# and use the first two.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# --- 1. VPC ------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # DNS names inside the VPC - required by EKS.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.projectname}-vpc" }
}

# --- 2. Subnets: 2 public + 2 private, each pair in a different AZ ------------
# cidrsubnet() cuts the /16 VPC range into /24 pieces:
#   public:  10.0.0.0/24, 10.0.1.0/24     private: 10.0.2.0/24, 10.0.3.0/24
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)

  # Things started here get a public IP automatically.
  map_public_ip_on_launch = true

  tags = { Name = "${var.projectname}-public-${count.index + 1}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  # Continue numbering right after the public subnets, so the ranges form an
  # unbroken chain: with 2 public subnets the private ones get index 2 and 3.
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + length(aws_subnet.public))

  tags = { Name = "${var.projectname}-private-${count.index + 1}" }
}

# --- 3. Internet Gateway -----------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.projectname}-igw" }
}

# --- 4. NAT Gateway ----------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${var.projectname}-nat-eip" }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = { Name = "${var.projectname}-nat" }

  depends_on = [aws_internet_gateway.main]
}

# --- 5. Route tables ---------------------------------------------------------
# Traffic inside the VPC  is always routed automatically
# we only add the "everything else"
# (0.0.0.0/0) route.

# Public subnets: everything else -> Internet Gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.projectname}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnets: everything else -> NAT Gateway (outgoing only).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.projectname}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- 6. Network ACLs ---------------------------------------------------------
# Unlike security groups, NACLs are
# STATELESS: replies are not allowed automatically, so we must also allow the
# "ephemeral" ports 1024-65535 that replies come back on.
# Rules are checked from the lowest rule_no up; anything not allowed is denied.
# The fine-grained filtering is done by the security groups (security.tf).

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  # Inbound 100: anything from inside the VPC (e.g. nodes -> NAT Gateway).
  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1" # all protocols
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Inbound 110: HTTP from the internet to the load balancer.
  ingress {
    rule_no    = 110
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Inbound 120/130: replies from the internet (to the NAT Gateway).
  ingress {
    rule_no    = 120
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  ingress {
    rule_no    = 130
    action     = "allow"
    protocol   = "udp"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Outbound: allow everything (security groups still control what is sent).
  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "${var.projectname}-public-nacl" }
}

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  # Inbound 100: anything from inside the VPC (control plane, other nodes,
  # load balancer health checks).
  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Inbound 110: TCP 1024-65535 from anywhere. This covers two things:
  #  - replies from the internet that come back through the NAT Gateway
  #  - user requests from the load balancer to the NodePort (30080). The NLB
  #    keeps the user's own IP address, so they arrive "from the internet".
  ingress {
    rule_no    = 110
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Inbound 120: UDP replies through the NAT Gateway.
  ingress {
    rule_no    = 120
    action     = "allow"
    protocol   = "udp"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Outbound: allow everything (it can only leave through the NAT Gateway).
  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "${var.projectname}-private-nacl" }
}
