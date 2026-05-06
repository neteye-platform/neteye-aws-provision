
locals {
  public_nodes_ip = jsondecode(data.external.cidr_expand.result.public_nodes_ip)
}

## ONE VPC
resource "aws_vpc" "main" {
  cidr_block           = data.external.cidr_expand.result.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project}-main-vpc"
  }
}

## SUBNET
# Private subnet (for nodes)
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = data.external.cidr_expand.result.private_subnet
  map_public_ip_on_launch = false
  availability_zone       = var.availability_zone
  tags = { Name = "${var.project}-private" }
}

# Public subnet (for NAT gateway)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = data.external.cidr_expand.result.public_subnet
  map_public_ip_on_launch = false
  availability_zone       = var.availability_zone
  tags = { Name = "${var.project}-public" }
}

## NI

# Create a network interface in the public subnet for each instance
resource "aws_network_interface" "public" {
  count           = local.node_count
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.main.id]
  private_ip = local.public_nodes_ip[count.index]
  source_dest_check = false
  tags = {
    Name = "${var.project}-node-public-eni-${count.index + 1}"
  }
}

# Attach the public network interface to each instance as eth1
resource "aws_network_interface_attachment" "public_iface" {
  count                = local.node_count
  instance_id          = aws_instance.node[count.index].id
  network_interface_id = aws_network_interface.public[count.index].id
  device_index         = 1
}


## INTERNET GATEWAY 

resource "aws_internet_gateway" "neteye-igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

# NAT Gateway in public subnet

resource "aws_nat_gateway" "main" {
  allocation_id = var.outgoing_ip_allocation_id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "${var.project}-nat-gw" }
}

# Public subnet -> Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.neteye-igw.id
  }

  tags = {
    Name = "${var.project}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private subnet -> NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}