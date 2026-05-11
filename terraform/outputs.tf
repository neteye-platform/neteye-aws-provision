output "instance_ids" {
  description = "EC2 instance IDs"
  value       = aws_instance.node[*].id
}

output "clusterIp" {
  description = "Cluster IP address"
  value       = data.external.cidr_expand.result.cluster_ip
}
