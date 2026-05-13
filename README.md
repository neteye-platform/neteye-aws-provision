# NetEye AWS Installation

Automated deployment of a [NetEye 4](https://www.neteye-blog.com/) monitoring cluster on AWS using **Terraform** for infrastructure provisioning and **Ansible** for OS-level configuration.

## Architecture Overview

The infrastructure deploys a multi-node NetEye cluster inside a single VPC with public and private subnets, leveraging Network Load Balancers for both internal service routing and external access.

```text
                        ┌─────────────────────────────────────────────────────────────────────┐
                        │                            AWS VPC (/22)                            │
                        │                                                                     │
     Internet           │   ┌───────────────────────── Public Subnet (/24) ──────────────┐    │
        │               │   │                                                            │    │
        │               │   │   ┌──────────────┐        ┌────────────────────────────┐   │    │
        ▼               │   │   │   Internet   │        │     NAT Gateway            │   │    │
  ┌───────────┐         │   │   │   Gateway    │        │  (Elastic IP: outgoing)    │   │    │
  │ Elastic IP│◄────────┼───┤   └──────┬───────┘        └────────────┬───────────────┘   │    │
  │ (Cluster) │         │   │          │                             │                   │    │
  └─────┬─────┘         │   │          ▼                             │                   │    │
        │               │   │   ┌──────────────┐                     │                   │    │
        │               │   │   │  Public NLB  │                     │                   │    │
        │               │   │   │ (443, 5665)  │                     │                   │    │
        │               │   │   └──────┬───────┘                     │                   │    │
        │               │   │          │            ┌────────────┐   │                   │    │
        │               │   │          │            │  ENI (eth1)│   │                   │    │
        │               │   │          │            │  per node  │   │                   │    │
        │               │   └──────────┼────────────┴────────────┴───┘                   │    │
        │               │              │                     ▲                           │    │
        │               │              ▼                     │                           │    │
        │               │   ┌───────────────────────── Private Subnet (/23) ─────────────┐    │
        │               │   │                                                            │    │
        │               │   │   ┌──────────────┐    ┌──────────┐  ┌──────────┐           │    │
        │               │   │   │ Internal NLB │    │  Node 1  │  │  Node 2  │   ...     │    │
        │               │   │   │  (services)  │◄──►│  (eth0)  │  │  (eth0)  │           │    │
        │               │   │   └──────────────┘    └──────────┘  └──────────┘           │    │
        │               │   │                                                            │    │
        │               │   │   ┌────────────────────────────────────────────────────┐   │    │
        │               │   │   │         VPC Endpoints (SSM, SSMMessages,           │   │    │
        │               │   │   │                   EC2Messages)                     │   │    │
        │               │   │   └────────────────────────────────────────────────────┘   │    │
        │               │   └────────────────────────────────────────────────────────────┘    │
        │               └─────────────────────────────────────────────────────────────────────┘
        │
        └──► Targets the Cluster VIP (floating IP managed by Pacemaker/Corosync)
```

### Key Components

| Component | Description |
| --------- | ----------- |
| **VPC** | A `/22` network automatically computed from the node IPs defined in `cluster_config.json` |
| **Private Subnet** (`/23`) | Hosts the EC2 instances (cluster nodes) on their primary interface (`eth0`) |
| **Public Subnet** (`/24`) | Hosts the NAT Gateway, Internet Gateway, and secondary ENIs (`eth1`) for each node |
| **Public NLB** | Internet-facing Network Load Balancer bound to the cluster Elastic IP; forwards exposed ports (default: 443, 5665) to the cluster VIP |
| **Internal NLB** | Private NLB for internal service routing (MySQL, Kibana, etc.); target groups are created during NetEye installation |
| **NAT Gateway** | Provides outbound internet access for nodes in the private subnet via a dedicated Elastic IP |
| **Internet Gateway** | Enables inbound/outbound connectivity for the public subnet |
| **EC2 Instances** | RHEL 8 nodes running NetEye, each with encrypted gp3 root + data volumes and dual NICs |
| **Security Groups** | `main-sg` allows unrestricted inter-node traffic + NLB-to-node on service ports; `nlb-sg` restricts public access to an IP allow-list |
| **IAM Roles & Policies** | SSM access for Session Manager, plus EC2/ELB permissions for automated cluster failover (VIP migration) |
| **VPC Endpoints** | Interface endpoints for SSM, SSMMessages, and EC2Messages — enables Session Manager without public IPs |
| **SSH Keys** | ED25519 key pairs generated per node; all public keys are distributed to every node for passwordless inter-node SSH |

### Cluster Failover

NetEye uses Pacemaker/Corosync for high-availability. On AWS, the cluster VIP cannot float via gratuitous ARP. Instead, each node is provisioned with IAM credentials that allow it to:

1. Reassign the cluster VIP (a secondary private IP) to its own ENI via `ec2:AssignPrivateIpAddresses`
2. Update the internal NLB target groups to point to the new active node

This is handled by the `cluster_failover_iam` policy attached to both the node instance role and a dedicated IAM user.

## Repository Structure

```text
src/
├── terraform/                  # Infrastructure as Code
│   ├── main.tf                 # Provider, locals, security group, EC2 instances
│   ├── variables.tf            # Input variables with defaults
│   ├── terraform.tfvars        # Environment-specific variable values
│   ├── networking.tf           # VPC, subnets, IGW, NAT GW, route tables, ENIs
│   ├── load-balancers.tf       # Public & internal NLBs, target groups, listeners
│   ├── ssm.tf                  # IAM role for SSM + VPC endpoints
│   ├── cluster_failover_iam.tf # IAM policies for VIP failover
│   ├── cluster_config.json     # Cluster topology (nodes, IPs, roles)
│   ├── outputs.tf              # Terraform outputs
│   └── helpers/
│       ├── get_cidr_blocks.py  # Computes VPC/subnet CIDRs from node IPs
│       └── userdata.sh.tpl     # Cloud-init script (SSH keys, repos, hostname, etc.)
└── ansible/
    └── convert_to_neteye.yaml  # Post-boot playbook: installs NetEye packages & configures OS
```

## Prerequisites

- **Terraform** >= 1.0
- **Python 3** (used by the CIDR helper script)
- **AWS CLI** configured with appropriate credentials
- Two pre-allocated **Elastic IPs**:
  - One for outbound NAT traffic
  - One for the public cluster endpoint
- A **RHEL 8 AMI** available in the target region
- A valid **NetEye subscription** (for repository access)

## Usage

### 1. Configure the cluster topology

Edit `src/terraform/cluster_config.json` to define your nodes:

```json
{
  "Hostname": "neteye.example.com",
  "Deployment": "aws",
  "Nodes": [
    { "addr": "192.168.47.1", "hostname": "neteye01.neteyelocal", "hostname_ext": "neteye01.aws.com", "id": 1, "roles": ["mariadb"] },
    { "addr": "192.168.47.2", "hostname": "neteye02.neteyelocal", "hostname_ext": "neteye02.aws.com", "id": 2, "roles": ["mariadb"] }
  ],
  "VotingOnlyNode": { ... }
}
```

> [!WARNING]
> Remember to set `Deployment` to `aws`!
>

### 2. Set your variables

Edit `src/terraform/terraform.tfvars`:

```hcl
outgoing_ip_allocation_id = "eipalloc-..."
cluster_ip_allocation_id  = "eipalloc-..."
neteye_version            = "4.48-sr1"
ip_filtering_allow_list   = ["203.0.113.0/32"]
```

### 3. Deploy infrastructure

```bash
cd src/terraform
terraform init
terraform plan
terraform apply
```

### 4. Run the Ansible playbook

Once the instances are up and cloud-init has completed (check for `/root/userdata_done`):

```bash
cd src/ansible
ansible-playbook -i /root/inventory.ini convert_to_neteye.yaml -e neteye_version=4.48-sr1
```

> **Note:** The playbook is intended to run **from one of the cluster nodes** (via SSM Session Manager), since nodes are in a private subnet with no direct SSH access from the internet.

### 5. Proceed with the standard NetEye installation

Proceed with the usual NetEye installation following the official [User Guide](https://neteye.guide/current/getting-started/system-installation/cluster.html)

## Accessing Nodes

Nodes have no public IP. Access is provided via **AWS Systems Manager Session Manager**:

```bash
aws ssm start-session --target <instance-id>
```

## Networking Details

- The VPC CIDR is automatically computed as a `/22` encompassing all node IPs
- The public subnet is the first `/24` of the VPC
- The private subnet is a `/23` from the remaining space
- Each node gets a secondary ENI in the public subnet for NLB target registration
- The cluster VIP is a random available IP from the public subnet, used as the NLB target

## Variables Reference

| Variable | Description | Default |
| -------- | ----------- | ------- |
| `aws_region` | AWS region | `eu-south-1` |
| `availability_zone` | AZ for all resources | `eu-south-1a` |
| `neteye_version` | NetEye version to deploy | — (required) |
| `ec2_ami` | RHEL 8 AMI ID | `ami-0611ece2c5afd38ef` |
| `instance_type` | EC2 instance type | `c6i.4xlarge` |
| `volume_group_size` | Data volume size (GB) | `60` |
| `exposed_ports` | Ports exposed via public NLB | `[443, 5665]` |
| `ip_filtering_allow_list` | CIDRs allowed through the NLB | — (required) |
| `outgoing_ip_allocation_id` | EIP allocation for NAT GW | — (required) |
| `cluster_ip_allocation_id` | EIP allocation for public endpoint | — (required) |
| `project` | Resource name prefix | `neteye` |
| `timezone` | Instance timezone | `Europe/Rome` |
