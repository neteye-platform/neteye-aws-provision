variable "aws_region" {
  description = "AWS region to deploy resources (e.g., eu-south-1)"
  type        = string
  default     = "eu-south-1"
}

variable "netmask" {
  description = "Netmask for node subnets (e.g., 24)"
  type        = string
  default     = "24"
}

variable "availability_zone" {
  description = "Availability zone to deploy resources (e.g., eu-south-1a)"
  type        = string
  default     = "eu-south-1a"
}

variable neteye_version {
  description = "Version of NetEye to deploy (e.g., 4.47)"
  type        = string
}

variable timezone {
  description = "Timezone for the instances (e.g., Europe/Rome)"
  type        = string
  default     = "Europe/Rome"
}

variable ec2_ami {
  description = "AMI ID for EC2 instances (e.g., ami-0611ece2c5afd38ef)"
  type        = string
  default     = "ami-0611ece2c5afd38ef"
}

variable "volume_group_size" {
  description = "Size in GB of the main vg00 volume group, used by default for NetEye services"
  type        = number
  default     = 60
}

variable outgoing_ip_allocation_id {
  description = "List of EIP allocation ID for outgoing traffic"
  type        = string
}

variable cluster_ip_allocation_id {
  description = "EIP allocation ID for the cluster IP"
  type        = string
}

variable exposed_ports {
  description = "List of ports to expose via the public NLB"
  type        = list(number)
  default     = [443, 5665]
}

variable ip_filtering_allow_list {
  description = "List of CIDR blocks allowed to access the cluster"
  type        = list(string)
}

variable project {
  description = "Project name for resource tagging"
  type        = string
  default     = "neteye"
}

variable "instance_type" {
  description = "EC2 instance type for the NetEye nodes (e.g., c6i.4xlarge)"
  type        = string
  default     = "c6i.4xlarge"
}

variable "additional_hostnames_allowed_for_outgoing" {
  description = "List of hostnames to resolve and allow for outgoing traffic, in addition to the default ones"
  type        = list(string)
  default     = []
}

variable "hostnames_allowed_for_outgoing" {
  description = "List of hostnames to resolve and allow for outgoing traffic"
  type        = list(string)
  # Minimum documented 
  default     = [
    "repo.wuerth-phoenix.com", 
    "api.neteye.cloud", 
    "cdn.redhat.com", 
    "cdn-ubi.redhat.com", 
    "cert-api.access.redhat.com", 
    "cert.cloud.redhat.com",
    "subscription.rhsm.redhat.com",
    "mirrors.fedoraproject.org",
    "2.rhel.pool.ntp.org",
    "grafana.com",
    "yum.centreon.com",
    "rubygems.org",
    "epr.elastic.co",
    # AWS-specific — only RHUI is needed here; SSM and S3 are
    # handled by VPC endpoints + self/prefix-list egress rules.
    "rhui.eu-south-1.aws.ce.redhat.com"
  ]
}

variable "ip_allowed_for_outgoing" {
  description = "List of CIDR blocks allowed for outgoing traffic (in addition to those resolved from hostnames)"
  type        = list(string)
  default     = []
}