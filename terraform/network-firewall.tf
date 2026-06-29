## AWS Network Firewall
# Inspects inbound traffic to the public NLB using the same IP allow lists
# that were previously only enforced by the NLB security group.

locals {
  # Combine web and data CIDRs for the stateless allow rule
  all_allowed_cidrs = distinct(concat(
    var.web_ip_filtering_allow_list,
    var.data_ip_filtering_allow_list,
  ))

  web_ports  = [for p in var.exposed_ports : p if p == 443]
  data_ports = [for p in var.exposed_ports : p if p != 443]
}

# --- Rule Groups ---

resource "aws_networkfirewall_rule_group" "allow_web" {
  capacity = 100
  name     = "${var.project}-allow-web"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      dynamic "stateful_rule" {
        for_each = local.web_ports
        content {
          action = "PASS"
          header {
            destination      = "ANY"
            destination_port = tostring(stateful_rule.value)
            direction        = "FORWARD"
            protocol         = "TCP"
            source           = "ANY"
            source_port      = "ANY"
          }
          rule_option {
            keyword  = "sid"
            settings = ["1${stateful_rule.value}"]
          }
        }
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = { Name = "${var.project}-allow-web" }
}

resource "aws_networkfirewall_rule_group" "allow_data" {
  capacity = 100
  name     = "${var.project}-allow-data"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      dynamic "stateful_rule" {
        for_each = local.data_ports
        content {
          action = "PASS"
          header {
            destination      = "ANY"
            destination_port = tostring(stateful_rule.value)
            direction        = "FORWARD"
            protocol         = "TCP"
            source           = "ANY"
            source_port      = "ANY"
          }
          rule_option {
            keyword  = "sid"
            settings = ["2${stateful_rule.value}"]
          }
        }
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = { Name = "${var.project}-allow-data" }
}

# Stateless rule: allow traffic from approved CIDRs, drop everything else
resource "aws_networkfirewall_rule_group" "allow_approved_cidrs" {
  capacity = 200
  name     = "${var.project}-allow-approved-cidrs"
  type     = "STATELESS"

  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {

        # Allow web CIDRs to web ports
        stateless_rule {
          priority = 10
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              dynamic "source" {
                for_each = var.web_ip_filtering_allow_list
                content {
                  address_definition = source.value
                }
              }
              dynamic "destination_port" {
                for_each = local.web_ports
                content {
                  from_port = destination_port.value
                  to_port   = destination_port.value
                }
              }
              protocols = [6] # TCP
            }
          }
        }

        # Allow data CIDRs to data ports
        stateless_rule {
          priority = 20
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              dynamic "source" {
                for_each = var.data_ip_filtering_allow_list
                content {
                  address_definition = source.value
                }
              }
              dynamic "destination_port" {
                for_each = local.data_ports
                content {
                  from_port = destination_port.value
                  to_port   = destination_port.value
                }
              }
              protocols = [6] # TCP
            }
          }
        }

        # Allow return traffic (established connections from VPC)
        stateless_rule {
          priority = 30
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              source {
                address_definition = aws_vpc.main.cidr_block
              }
              protocols = [6] # TCP
            }
          }
        }
      }
    }
  }

  tags = { Name = "${var.project}-allow-approved-cidrs" }
}

# --- Firewall Policy ---

resource "aws_networkfirewall_firewall_policy" "main" {
  name = "${var.project}-fw-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:drop"]
    stateless_fragment_default_actions = ["aws:drop"]

    stateless_rule_group_reference {
      priority     = 1
      resource_arn = aws_networkfirewall_rule_group.allow_approved_cidrs.arn
    }

    stateful_default_actions = ["aws:drop_established"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_rule_group_reference {
      priority     = 1
      resource_arn = aws_networkfirewall_rule_group.allow_web.arn
    }

    stateful_rule_group_reference {
      priority     = 2
      resource_arn = aws_networkfirewall_rule_group.allow_data.arn
    }
  }

  tags = { Name = "${var.project}-fw-policy" }
}

# --- Firewall ---

resource "aws_networkfirewall_firewall" "main" {
  name                = "${var.project}-network-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn
  vpc_id              = aws_vpc.main.id

  subnet_mapping {
    subnet_id = aws_subnet.firewall.id
  }

  tags = { Name = "${var.project}-network-firewall" }
}

# Extract the firewall endpoint ID for routing
locals {
  fw_endpoint_id = [
    for ss in aws_networkfirewall_firewall.main.firewall_status[0].sync_states :
    ss.attachment[0].endpoint_id
    if ss.availability_zone == var.availability_zone
  ][0]
}
