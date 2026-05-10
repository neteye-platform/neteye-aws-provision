## INTERNAL LOAD BALANCER
# Internal load balancer (mysql, kibana, etc)
# Note: target groups and listeners are created during the installation process

resource "aws_lb" "internal" {
  name               = "${var.project}-int-nlb"
  load_balancer_type = "network"
  internal           = true
  subnets            = [aws_subnet.private.id]

  enable_cross_zone_load_balancing = false

  security_groups    = [aws_security_group.main.id]

  tags = { Name = "${var.project}-int-nlb" }
}

## PUBLIC LOAD BALANCER
# Public load balancer (VIP access from the outside + other exposed ports)
resource "aws_lb" "public" {
  name               = "${var.project}-public-nlb"
  load_balancer_type = "network"
  internal           = false
  security_groups    = [aws_security_group.nlb.id]

  subnet_mapping {
    subnet_id     = aws_subnet.public.id
    allocation_id = var.cluster_ip_allocation_id
  }

  enable_cross_zone_load_balancing = false

  tags = { Name = "${var.project}-public-nlb" }
}

resource "aws_lb_target_group" "vip" {
  for_each = { for port in var.exposed_ports : port => port }

  name        = substr("${var.project}-tg-${each.value}", 0, 32)
  port        = each.value
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    protocol = "TCP"
    port     = tostring(each.value)
    interval = 10
    healthy_threshold  = 2

  }

  tags = { Name = "${var.project}-tg-${each.value}" }
}

resource "aws_lb_listener" "vip" {
  for_each = { for port in var.exposed_ports : port => port }

  load_balancer_arn = aws_lb.public.arn
  port              = each.value
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vip[each.key].arn
  }
}

# Target is the ClusterIp (VIP)
resource "aws_lb_target_group_attachment" "vip" {
  for_each = { for port in var.exposed_ports : port => port }

  target_group_arn  = aws_lb_target_group.vip[each.key].arn
  target_id         = data.external.cidr_expand.result.cluster_ip
  port              = each.value

  depends_on = [
    aws_subnet.public
  ]
}
resource "aws_security_group" "nlb" {
  name        = "${var.project}-nlb-sg"
  description = "Public ingress to the internet-facing NLB"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = { for port in var.exposed_ports : port => port }
    content {
      description = "Allow TCP ${ingress.value} from approved client CIDRs"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.ip_filtering_allow_list
    }
  }

  egress {
    description = "Allow NLB traffic to targets in the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = {
    Name = "${var.project}-nlb-sg"
  }
}
