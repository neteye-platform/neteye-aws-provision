#!/usr/bin/env python3

import sys
import json
import ipaddress
import random


# Accept only private network definitions
data = json.load(sys.stdin)

nodes_ip = json.loads(data.get("nodes_ip", "[]"))  # deserialize back to list

result = {}

# Always use /22
vpc_subnet = ipaddress.IPv4Network(f"{nodes_ip[0]}/22", strict=False)
result["vpc_cidr_block"] = str(vpc_subnet)
result["vpc_prefix"] = str(vpc_subnet.prefixlen)


# First /24 (1/4)
subnet_1 = list(vpc_subnet.subnets(new_prefix=24))[0]
result["public_subnet"] = str(subnet_1)
result["public_subnet_prefix"] = str(subnet_1.prefixlen)

# Next /23 after the /24, aligned to /23 boundary
# Find all /23s in the /22, pick the first one that does not overlap with subnet_1
subnets_23 = list(vpc_subnet.subnets(new_prefix=23))
subnet_2 = None
for s in subnets_23:
    if not s.overlaps(subnet_1):
        subnet_2 = s
        break
if subnet_2:
    result["private_subnet"] = str(subnet_2)
    result["private_subnet_prefix"] = str(subnet_2.prefixlen)

# Reserve nodes IPs in the public subnet, starting from the 6th host (first 5 are reserved for AWS)
result["public_nodes_ip"] = json.dumps(
    [str(h) for h in list(subnet_1.hosts())[5 : len(nodes_ip) + 5]]
)

# Get a random IP from the public subnet that is not in nodes_ip, starting from the 6th host (first 5 are reserved for AWS)
ips = list(subnet_1.hosts())[5:]
hosts = [str(h) for h in ips if str(h) not in nodes_ip]
result["cluster_ip"] = hosts[random.randint(0, len(hosts) - 1)]

print(json.dumps(result))
