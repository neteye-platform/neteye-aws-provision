#!/bin/bash

# Install SSM agent for Session Manager access
dnf install -y https://s3.eu-south-1.amazonaws.com/amazon-ssm-eu-south-1/latest/linux_amd64/amazon-ssm-agent.rpm

systemctl enable --now amazon-ssm-agent

# Inter-node SSH keys
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Install this node's private key
cat <<'PRIVKEY' > /root/.ssh/id_ed25519
${private_key}
PRIVKEY
chmod 600 /root/.ssh/id_ed25519

# Install all nodes' public keys into authorized_keys
cat <<'PUBKEYS' >> /root/.ssh/authorized_keys
${public_keys}
PUBKEYS
chmod 600 /root/.ssh/authorized_keys

touch /root/.ssh/config
chmod 600 /root/.ssh/config

# NetEye temporary repos to install the actual repo definitions
cat <<EOT > /etc/yum.repos.d/Rhel-NetEye-temporary.repo
# NetEye temporary repo for installing ne packages and repo definitions
[neteye]
name=NetEye
baseurl=https://repo.wuerth-phoenix.com/rhel8/neteye-${DNF0}
gpgcheck=0
enabled=0

[neteye-os]
name=NetEye OS
baseurl=https://repo.wuerth-phoenix.com/rhel8/neteye-${DNF0}-os
gpgcheck=0
enabled=0

[neteye-epel]
name=NetEye EPEL
baseurl=https://repo.wuerth-phoenix.com/rhel8/neteye-${DNF0}-epel
gpgcheck=0
enabled=0
EOT

# # Inventory file with internal hostnames
cat <<'INVENTORY' > /root/inventory.ini
[nodes]
%{ for n in all_nodes ~}
${n.hostname}
%{ endfor ~}
INVENTORY

# Packages from RHEL repos
dnf install -y python36 unzip jq
# Packages from NetEye repos
dnf install -y ansible-core neteye-ansible-communitygeneral-collection neteye-ansible-communitymysql-collection neteye-ansible-posix-collection neteye-ansible-communitycrypto-collection --enablerepo=neteye,neteye-os,neteye-epel

# Set hostname and timezone
hostnamectl set-hostname "${hostname_ext}"
timedatectl set-timezone "${timezone}"

# /etc/hosts – map cluster IPs to hostnames for all nodes
cat <<'HOSTS' >> /etc/hosts
${cluster_ip} ${cluster_hostname}
${cluster_ip} neteye.neteyelocal
%{ for n in all_nodes ~}
${n.addr} ${n.hostname} ${(split(".", n.hostname))[0]}
%{ endfor ~}
HOSTS

# Add trusted fingerprints for all nodes to known_hosts to avoid SSH warnings
%{ for n in all_nodes ~}
ssh-keyscan ${n.hostname} >> ~/.ssh/known_hosts
%{ endfor ~}
 
# Rename connections to match the device name, so that they are consistent across reboots and can be easily referenced in Ansible playbooks
nmcli -t -f NAME,DEVICE connection show --active | while IFS=: read -r name dev; do
  if [ -n "$dev" ]; then
    nmcli connection modify "$name" connection.id "$dev"
  fi
done

echo "${cluster_config}" > /etc/neteye-cluster.template

# Write cluster configuration changing the cluster IP, CIDR and cluster interface.
jq \
  '.ClusterIp = $ip 
   | .ClusterCIDR = 24
   | .ClusterInterface = "eth0"' \
  --arg ip "${cluster_ip}" \
<<'EOF' > /etc/neteye-cluster
${cluster_config}
EOF

# Create AWS credentials file for cluster failover operations
mkdir -p /root/.aws
chmod 700 /root/.aws
cat <<'AWSCRED' > /root/.aws/credentials
[default]
aws_access_key_id = ${aws_access_key_id}
aws_secret_access_key = ${aws_secret_access_key}
AWSCRED
chmod 600 /root/.aws/credentials

# Write project name to a file for later use in Ansible playbooks
echo "${project}" > /root/.aws_project

cat <<'AWSREGION'> /root/.aws/config
[default]
region = ${aws_region}
AWSREGION
chmod 600 /root/.aws/config

# Set PHP timezone
mkdir -p /neteye/local/php/conf/php.d
cat <<'PHPINI' > /neteye/local/php/conf/php.d/30-timezone.ini
[Date]
date.timezone = ${timezone}
PHPINI

touch /root/userdata_done