resource "aws_iam_role_policy" "cluster_failover" {
  name = "${var.project}-cluster-failover"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:AssignPrivateIpAddresses",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstances",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      },
      {
        Sid    = "ELBFailover"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:ModifyTargetGroup"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.project}-node-profile"
  role = aws_iam_role.node.name
}

resource "aws_iam_user" "cluster_node" {
  name = "${var.project}-cluster-node"
  tags = { Name = "${var.project}-cluster-node" }
}

resource "aws_iam_access_key" "cluster_node" {
  user = aws_iam_user.cluster_node.name
}

resource "aws_iam_group" "cluster_node" {
  name = "${var.project}-cluster-node"
}

resource "aws_iam_group_membership" "cluster_node" {
  name  = "${var.project}-cluster-node"
  group = aws_iam_group.cluster_node.name
  users = [aws_iam_user.cluster_node.name]
}

resource "aws_iam_group_policy" "cluster_node" {
  name   = "${var.project}-cluster-failover"
  group  = aws_iam_group.cluster_node.name
  policy = aws_iam_role_policy.cluster_failover.policy
}