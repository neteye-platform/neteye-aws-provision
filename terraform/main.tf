provider "aws" {
  region = var.aws_region
}

## VARIABLES DEFINITION
locals {
  # Load cluster configuration from JSON file
  cluster_config = jsondecode(file("${path.module}/cluster_config.json"))

  # Extract node information and compute padded IPs for sorting
  main_nodes    = local.cluster_config.Nodes
  voting_nodes  = try([local.cluster_config.VotingOnlyNode], [])
  elastic_nodes = try(local.cluster_config.ElasticOnlyNodes, [])
  all_nodes     = concat(local.main_nodes, local.voting_nodes, local.elastic_nodes)
  node_count    = length(local.all_nodes)
}

# Use the minimum IP and netmask to calculate the CIDR block for the VPC
data "external" "cidr_expand" {
  program = ["python3", "${path.module}/helpers/get_cidr_blocks.py"]
  query = {
    nodes_ip     = jsonencode([for node in local.all_nodes : node.addr])
  }
}

## IAM
resource "aws_security_group" "main" {
  name        = "${var.project}-sg"
  description = "Inter-node traffic, NLB-to-node service ports, unrestricted outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All traffic between cluster nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  dynamic "ingress" {
    for_each = var.exposed_ports
    content {
      description     = "Service port ${ingress.value} from NLB"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.nlb.id]
    }
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-sg"
  }
}

resource "tls_private_key" "vm" {
  count     = local.node_count
  algorithm = "ED25519"
}

## EC2 Instances
resource "aws_instance" "node" {
  count               = local.node_count
  ami                 = var.ec2_ami
  instance_type       = var.instance_type
  subnet_id           = aws_subnet.private.id
  private_ip          = local.all_nodes[count.index]["addr"]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name
  security_groups = [aws_security_group.main.id]

  user_data = templatefile("${path.module}/helpers/userdata.sh.tpl", {
    hostname = local.all_nodes[count.index]["hostname_ext"],
    DNF0             = var.neteye_version
    private_key      = tls_private_key.vm[count.index].private_key_openssh
    public_keys      = join("\n", tls_private_key.vm[*].public_key_openssh)
    cluster_config = jsonencode(local.cluster_config)
    int_nlb_dns_name = aws_lb.internal.dns_name
    all_private_ips  = join(", ", local.all_nodes[*].addr)
    cluster_ip       = data.external.cidr_expand.result.cluster_ip
    cluster_hostname  = local.cluster_config.Hostname
    hostname_ext     = local.all_nodes[count.index]["hostname_ext"]
    timezone         = var.timezone
    all_nodes = local.all_nodes
    aws_access_key_id    = aws_iam_access_key.cluster_node.id
    aws_secret_access_key = aws_iam_access_key.cluster_node.secret
    project              = var.project
    aws_region          = var.aws_region
  })

  
  tags = {
    Name = local.all_nodes[count.index]["hostname_ext"]
  }

  depends_on = [
    aws_route_table_association.private,
    aws_route_table_association.public,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages,
  ]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 40
    delete_on_termination = true
    encrypted             = true
  }

  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = var.volume_group_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }
}
