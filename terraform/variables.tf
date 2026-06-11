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

variable "default_volume_group_size" {
  description = "Size in GB of the main vg00 volume group, used by default for NetEye services"
  type        = number
  default     = 60
}

variable "instances_properties" {
  description = "Optional per-host override for instance properties. Keys must match node hostname_ext in cluster_config.json. Each object can define instance_type and/or volume_group_size. Missing fields fall back to defaults."
  type        = map(object({
    instance_type     = optional(string)
    volume_group_size = optional(number)
  }))
  default     = {}
}

variable outgoing_ip_allocation_id {
  description = "List of EIP allocation ID for outgoing traffic"
  type        = string
}

variable cluster_ip_allocation_id {
  description = "EIP allocation ID for the cluster IP"
  type        = string
}

variable "enable_shield_advanced" {
  description = "Whether to protect the public NLB with AWS Shield Advanced"
  type        = bool
  default     = false
}

variable exposed_ports {
  description = "List of ports to expose via the public NLB"
  type        = list(number)
  default     = [443, 5665, 4222]
}

variable web_ip_filtering_allow_list {
  description = "List of CIDR blocks allowed to access the WEB interface of the cluster"
  type        = list(string)
}

variable data_ip_filtering_allow_list {
  description = "List of CIDR blocks allowed to contact the cluster for data collection (e.g., from satellite sites)"
  type        = list(string)
}

variable project {
  description = "Project name for resource tagging"
  type        = string
  default     = "neteye"
}

variable "default_instance_type" {
  description = "Default EC2 instance type for the NetEye nodes (e.g., c6i.4xlarge)"
  type        = string
  default     = "c6i.4xlarge"
}

variable "ip_allowed_for_outgoing" {
  description = "List of CIDR blocks allowed for outgoing traffic"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
