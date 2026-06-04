#!/usr/bin/env python3

import ipaddress
import json
import random
import sys
from typing import NoReturn

PUBLIC_SUBNET_PREFIX = 24
DEFAULT_PRIVATE_SUBNET_PREFIX = 23
MIN_PRIVATE_SUBNET_PREFIX = 20
AWS_RESERVED_HOST_COUNT = 3


def fail(message: str) -> NoReturn:
    print(message, file=sys.stderr)
    sys.exit(1)


def usable_aws_hosts(subnet: ipaddress.IPv4Network) -> list[ipaddress.IPv4Address]:
    return list(subnet.hosts())[AWS_RESERVED_HOST_COUNT:]


def parse_nodes_ip(raw_nodes_ip: str) -> list[ipaddress.IPv4Address]:
    try:
        nodes = json.loads(raw_nodes_ip)
    except json.JSONDecodeError as error:
        fail(f"Invalid nodes_ip JSON: {error}")

    if not nodes:
        fail("nodes_ip must contain at least one IP address")

    try:
        return [ipaddress.IPv4Address(node) for node in nodes]
    except ipaddress.AddressValueError as error:
        fail(f"Invalid IPv4 address in nodes_ip: {error}")


def find_private_subnet(
    vpc_subnet: ipaddress.IPv4Network,
    node_addresses: list[ipaddress.IPv4Address],
) -> tuple[ipaddress.IPv4Network, ipaddress.IPv4Network]:
    for private_prefix in range(
        DEFAULT_PRIVATE_SUBNET_PREFIX,
        MIN_PRIVATE_SUBNET_PREFIX - 1,
        -1,
    ):
        candidate_vpc = ipaddress.IPv4Network(
            f"{node_addresses[0]}/{private_prefix - 1}",
            strict=False,
        )
        if not candidate_vpc.subnet_of(vpc_subnet):
            continue
        if any(node not in candidate_vpc for node in node_addresses):
            continue

        for subnet in candidate_vpc.subnets(new_prefix=private_prefix):
            usable_hosts = set(usable_aws_hosts(subnet))
            if all(node in usable_hosts for node in node_addresses):
                return candidate_vpc, subnet

    fail(
        "No private subnet can contain all requested node IPs as usable AWS "
        f"addresses from /{DEFAULT_PRIVATE_SUBNET_PREFIX} through "
        f"/{MIN_PRIVATE_SUBNET_PREFIX}. Check that the IPs are not the subnet "
        "network address, first three host addresses, or broadcast address for "
        "all supported subnet sizes."
    )


def find_public_subnet(
    vpc_subnet: ipaddress.IPv4Network,
    private_subnet: ipaddress.IPv4Network,
) -> ipaddress.IPv4Network:
    for subnet in vpc_subnet.subnets(new_prefix=PUBLIC_SUBNET_PREFIX):
        if not subnet.overlaps(private_subnet):
            return subnet

    fail(f"No public /{PUBLIC_SUBNET_PREFIX} subnet available outside {private_subnet}")


# Accept only private network definitions
data = json.load(sys.stdin)

node_addresses = parse_nodes_ip(data.get("nodes_ip", "[]"))

result = {}

initial_vpc_subnet = ipaddress.IPv4Network(
    f"{node_addresses[0]}/{MIN_PRIVATE_SUBNET_PREFIX - 1}",
    strict=False,
)
vpc_subnet, private_subnet = find_private_subnet(initial_vpc_subnet, node_addresses)

result["vpc_cidr_block"] = str(vpc_subnet)
result["vpc_prefix"] = str(vpc_subnet.prefixlen)
result["private_subnet"] = str(private_subnet)
result["private_subnet_prefix"] = str(private_subnet.prefixlen)

public_subnet = find_public_subnet(vpc_subnet, private_subnet)
result["public_subnet"] = str(public_subnet)
result["public_subnet_prefix"] = str(public_subnet.prefixlen)

public_hosts = usable_aws_hosts(public_subnet)

# Reserve one public ENI IP per node, skipping AWS-reserved addresses.
result["public_nodes_ip"] = json.dumps(
    [str(host) for host in public_hosts[: len(node_addresses)]]
)

# Get a random public-subnet IP that does not collide with public node ENIs.
public_node_ips = set(json.loads(result["public_nodes_ip"]))
cluster_hosts = [str(host) for host in public_hosts if str(host) not in public_node_ips]
if not cluster_hosts:
    fail(f"No available cluster IP left in {public_subnet}")

result["cluster_ip"] = random.choice(cluster_hosts)

print(json.dumps(result))
