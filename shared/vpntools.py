"""ARM discovery and local validation for the developer VPN notebook."""

import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import socket
import ssl
import subprocess
import sys
from typing import Any
from urllib.parse import urlsplit
from urllib.request import urlopen
import xml.etree.ElementTree as ET
import zipfile

import utils
from validationtools import _run_json


OWNER = "citadel-developer-vpn"


def notebook_defaults(overrides: dict, *, from_azd: bool = True) -> dict:
    snapshot = _run_json(["azd", "env", "get-values", "--output", "json"]) if from_azd else {}
    if not isinstance(snapshot, dict):
        raise ValueError("The active azd environment must return a JSON object.")
    aliases = {
        "expected_subscription_id": ("AZURE_SUBSCRIPTION_ID",),
        "governance_hub_resource_group": ("AZURE_RESOURCE_GROUP", "GOVERNANCE_HUB_RESOURCE_GROUP"),
        "location": ("AZURE_LOCATION", "LOCATION"),
        "primary_vnet_id": ("PRIMARY_VNET_ID", "AZURE_VNET_RESOURCE_ID", "VNET_RESOURCE_ID"),
        "apim_name": ("APIM_NAME", "AZURE_APIM_NAME"),
        "vpn_resource_group": ("VPN_RESOURCE_GROUP",),
        "resource_prefix": ("VPN_RESOURCE_PREFIX",),
    }

    def supplied(value: Any) -> bool:
        return isinstance(value, str) and bool(value.strip()) and value.strip() != "REPLACE"

    resolved = {}
    for name, keys in aliases.items():
        value = overrides.get(name)
        if value is not None and not isinstance(value, str):
            raise ValueError(f"{name} must be a string override or None for automatic configuration.")
        if not supplied(value):
            value = next((snapshot[key] for key in keys if supplied(snapshot.get(key))), None)
        resolved[name] = value.strip() if supplied(value) else None
    require_values(expected_subscription_id=resolved["expected_subscription_id"],
                   governance_hub_resource_group=resolved["governance_hub_resource_group"])
    if resolved["vpn_resource_group"] is None:
        primary_group = resolved["governance_hub_resource_group"]
        base = primary_group if len(primary_group) <= 86 else (
            primary_group[:77] + "-" + hashlib.sha256(primary_group.lower().encode()).hexdigest()[:8])
        resolved["vpn_resource_group"] = base + "-vpn"
    if resolved["resource_prefix"] is None:
        resolved["resource_prefix"] = "citadel-vpn"
    utils.print_info("Configuration resolved from explicit overrides, the active azd environment and VPN defaults.")
    return resolved


def discover_local_networks() -> list[str]:
    if sys.platform == "win32":
        prefixes = _run_json([
            "powershell", "-NoProfile", "-NonInteractive", "-Command",
            "$ErrorActionPreference = 'Stop'; ConvertTo-Json -Compress -InputObject "
            "@(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore | "
            "Select-Object -ExpandProperty DestinationPrefix -Unique)",
        ])
    elif sys.platform.startswith("linux"):
        routes = _run_json(["ip", "-j", "-4", "route", "show", "table", "all"])
        prefixes = [route["dst"] for route in routes if route.get("dst") not in (None, "default")]
    elif sys.platform == "darwin":
        command = ["netstat", "-rn", "-f", "inet"]
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=30, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            utils.print_error(f"Cannot discover local IPv4 routes: {error}")
            raise
        if result.returncode:
            utils.print_error(result.stderr.strip())
            raise RuntimeError("Cannot discover local routes; set local_network_cidrs explicitly.")
        prefixes = []
        for line in result.stdout.splitlines():
            fields = line.split()
            if not fields or not re.fullmatch(r"\d+(?:\.\d+){0,3}(?:/\d+)?", fields[0]):
                continue
            address, separator, mask = fields[0].partition("/")
            default_mask = str(len(address.split(".")) * 8)
            address = ".".join(address.split(".") + ["0"] * (4 - len(address.split("."))))
            prefixes.append(address + "/" + (mask if separator else default_mask))
    else:
        raise RuntimeError("Automatic local route discovery is unsupported; set local_network_cidrs explicitly.")
    if not isinstance(prefixes, list) or not all(isinstance(value, str) for value in prefixes):
        raise ValueError("Local route discovery did not return an IPv4 prefix list.")
    private_blocks = [ipaddress.ip_network(block) for block in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")]
    networks = set()
    for prefix in prefixes:
        network = ipaddress.ip_network(prefix, strict=False)
        if network.version == 4 and any(network.subnet_of(block) for block in private_blocks):
            networks.add(str(network))
    if not networks:
        raise ValueError("No private IPv4 routes detected. Set local_network_cidrs explicitly after checking the local network.")
    result = sorted(networks)
    utils.print_info(f"Detected local/corporate private IPv4 routes: {result}")
    return result


def az_json(*arguments: str, subscription: str | None = None, timeout: int = 300,
            expect_json: bool = True) -> Any:
    executable = shutil.which("az")
    if not executable:
        raise RuntimeError("Azure CLI is missing. Install it and run az login before continuing.")
    command = [executable, *arguments]
    if subscription:
        command.extend(["--subscription", subscription])
    command.extend(["--only-show-errors", "--output", "json"])
    utils.format_command(command, diagnostic=True)
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        utils.print_error(f"Azure CLI could not complete: {error}")
        raise
    if result.returncode:
        utils.print_error(result.stderr.strip() or result.stdout.strip())
        raise RuntimeError(f"Azure CLI failed: {' '.join(arguments[:3])}")
    if not expect_json:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        operation = "az " + " ".join(arguments[:3])
        detail = "empty stdout" if not result.stdout.strip() else (
            f"invalid JSON at line {error.lineno}, column {error.colno}")
        utils.format_command(command, title="Command requiring JSON output")
        utils.print_error(f"{operation} returned {detail}; no default or partial result will be used.")
        raise RuntimeError(f"Expected Azure CLI JSON output from {operation} ({detail}).") from error


def require_values(**values: Any) -> None:
    def missing(value: Any) -> bool:
        if isinstance(value, str):
            return not value.strip() or "REPLACE" in value
        if isinstance(value, (list, tuple)):
            return not value or any(missing(item) for item in value)
        if isinstance(value, dict):
            return not value or any(missing(item) for item in value.values())
        return value is None

    names = [name for name, value in values.items() if missing(value)]
    if names:
        raise ValueError(f"Set these notebook inputs before continuing: {', '.join(names)}")


def coordinates(resource_id: str, resource_type: str) -> tuple[str, str, str]:
    parts = resource_id.strip("/").split("/")
    if (len(parts) != 8 or parts[0].lower() != "subscriptions"
            or parts[2].lower() != "resourcegroups" or parts[4].lower() != "providers"
            or "/".join(parts[5:7]).lower() != resource_type.lower()):
        raise ValueError(f"Expected a full {resource_type} resource ID: {resource_id}")
    return parts[1], parts[3], parts[7]


def validate_networks(hub: str, pool: str, azure_prefixes: list[str],
                      local_prefixes: list[str]) -> dict[str, str]:
    require_values(local_network_cidrs=local_prefixes)
    hub_net, pool_net = (ipaddress.ip_network(value, strict=True) for value in (hub, pool))
    for network in (hub_net, pool_net):
        if network.version != 4 or not any(network.subnet_of(ipaddress.ip_network(block))
                                          for block in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")):
            raise ValueError("VPN hub and client pool must use RFC1918 IPv4 CIDRs.")
    if hub_net.prefixlen > 26:
        raise ValueError("Hub needs /26 or larger for its /27 GatewaySubnet and dedicated /28 DNS subnet.")
    if pool_net.prefixlen > 29 or pool_net.prefixlen < 16:
        raise ValueError("Use a client address pool between /16 and /29.")
    networks = [("hub", hub_net), ("client pool", pool_net)]
    others = [(value, ipaddress.ip_network(value, strict=True))
              for value in azure_prefixes + local_prefixes]
    for label, network in networks:
        for other_label, other in networks + others:
            if label != other_label and network.overlaps(other):
                raise ValueError(f"{label} {network} overlaps {other_label} {other}")
    gateway = next(hub_net.subnets(new_prefix=27))
    resolver = ipaddress.IPv4Network((int(hub_net.network_address) + 32, 28))
    return {"gatewaySubnet": str(gateway), "resolverSubnet": str(resolver),
            "resolverIp": str(resolver.network_address + 5)}


def _owned_by_primary_vnet(tags: dict | None, primary_vnet_id: str) -> bool:
    tags = tags or {}
    tagged_vnet = tags.get("primary-vnet-id")
    return (tags.get("managed-by") == OWNER and isinstance(tagged_vnet, str)
            and tagged_vnet.lower() == primary_vnet_id.lower())


def check_group(subscription: str, group: str, primary_vnet_id: str) -> bool:
    if not isinstance(primary_vnet_id, str) or not primary_vnet_id.strip() or primary_vnet_id == "REPLACE":
        raise ValueError("primary_vnet_id is unresolved. Run discovery and preview (Steps 2 and 4) first.")
    coordinates(primary_vnet_id, "Microsoft.Network/virtualNetworks")
    exists = az_json("group", "exists", "--name", group, subscription=subscription)
    if exists:
        resource_group = az_json("group", "show", "--name", group, subscription=subscription)
        if not _owned_by_primary_vnet(resource_group.get("tags"), primary_vnet_id):
            raise ValueError("VPN resource group already exists but is not owned by this runbook for this primary VNet.")
    return bool(exists)


def inspect_primary(subscription: str, primary_group: str, primary_vnet_id: str | None,
                    vpn_group: str, prefix: str, apim_name: str | None = None) -> tuple[dict, list[str]]:
    if not re.fullmatch(r"[a-zA-Z0-9_().-]{1,90}", vpn_group) or vpn_group.endswith("."):
        raise ValueError("Use a valid dedicated Azure resource group name (1-90 characters, no trailing period).")
    if not primary_vnet_id or primary_vnet_id == "REPLACE":
        subnet_id = ""
        if apim_name:
            apim = az_json("apim", "show", "--resource-group", primary_group, "--name", apim_name,
                           subscription=subscription)
            subnet_id = (apim.get("virtualNetworkConfiguration") or {}).get("subnetResourceId", "")
        if subnet_id:
            primary_vnet_id = subnet_id.rsplit("/subnets/", 1)[0]
        else:
            endpoints = az_json("network", "private-endpoint", "list", "--resource-group", primary_group,
                                subscription=subscription)
            candidates = {endpoint["subnet"]["id"].rsplit("/subnets/", 1)[0] for endpoint in endpoints}
            if len(candidates) == 1:
                primary_vnet_id = candidates.pop()
            elif candidates:
                raise ValueError("Primary private endpoints span multiple VNets. Set primary_vnet_id explicitly.")
            else:
                vnets = az_json("network", "vnet", "list", "--resource-group", primary_group, subscription=subscription)
                if len(vnets) != 1:
                    raise ValueError("Cannot identify one primary VNet from the RG/APIM/private endpoints. Set primary_vnet_id explicitly.")
                primary_vnet_id = vnets[0]["id"]
    vnet_subscription, vnet_group, _ = coordinates(primary_vnet_id, "Microsoft.Network/virtualNetworks")
    if vpn_group.lower() in (primary_group.lower(), vnet_group.lower()):
        raise ValueError("Use a separate VPN resource group, not the primary or BYO VNet resource group.")
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9-]{0,39}", prefix):
        raise ValueError("resource_prefix must contain 1-40 letters, digits or hyphens and start with a letter/digit.")
    vnet = az_json("network", "vnet", "show", "--ids", primary_vnet_id, subscription=vnet_subscription)
    check_group(subscription, vpn_group, primary_vnet_id)
    prefixes = list(vnet["addressSpace"]["addressPrefixes"])
    expected_hub_id = f"/subscriptions/{subscription}/resourceGroups/{vpn_group}/providers/Microsoft.Network/virtualNetworks/{prefix}-vnet"
    for peering in vnet.get("virtualNetworkPeerings", []):
        remote_id = peering["remoteVirtualNetwork"]["id"]
        if remote_id.lower() == expected_hub_id.lower():
            if peering["name"] != f"{prefix}-to-vpn":
                raise ValueError("An unmanaged peering already targets this VPN hub; resolve it before deployment.")
            continue
        if peering.get("useRemoteGateways"):
            raise ValueError("Primary VNet already uses another remote gateway; Azure permits only one.")
        remote_subscription, _, _ = coordinates(remote_id, "Microsoft.Network/virtualNetworks")
        remote = az_json("network", "vnet", "show", "--ids", remote_id, subscription=remote_subscription)
        prefixes.extend(remote["addressSpace"]["addressPrefixes"])
    for subnet in vnet.get("subnets", []):
        if subnet["name"].lower() in ("gatewaysubnet", "routeserversubnet"):
            raise ValueError("Primary VNet has a gateway/route-server subnet. Review transit with your network owner first.")
        route_table_id = (subnet.get("routeTable") or {}).get("id")
        if route_table_id:
            table = az_json("network", "route-table", "show", "--ids", route_table_id,
                            subscription=vnet_subscription)
            if table.get("disableBgpRoutePropagation"):
                raise ValueError(f"Gateway route propagation is disabled on route table {table['name']}.")
            utils.print_warning(f"Review UDRs on {table['name']} for P2S return-path overrides; this notebook will not edit them.")
    return vnet, prefixes


def discover_zones(subscription: str, primary_group: str, vnet: dict,
                   extra_zone_ids: list[str]) -> list[str]:
    vnet_subscription, _, _ = coordinates(vnet["id"], "Microsoft.Network/virtualNetworks")
    selected = {zone_id.lower(): zone_id for zone_id in extra_zone_ids}
    for scope in sorted({subscription, vnet_subscription}):
        zones = az_json("network", "private-dns", "zone", "list", subscription=scope)
        for zone in zones:
            zone_sub, zone_group, zone_name = coordinates(zone["id"], "Microsoft.Network/privateDnsZones")
            links = az_json("network", "private-dns", "link", "vnet", "list",
                            "--resource-group", zone_group, "--zone-name", zone_name, subscription=zone_sub)
            owned = scope == subscription and zone_group.lower() == primary_group.lower()
            linked = any(link["virtualNetwork"]["id"].lower() == vnet["id"].lower() for link in links)
            if owned or linked:
                selected[zone["id"].lower()] = zone["id"]
    endpoints = az_json("network", "private-endpoint", "list", "--resource-group", primary_group,
                        subscription=subscription)
    for endpoint in endpoints:
        groups = az_json("network", "private-endpoint", "dns-zone-group", "list",
                         "--resource-group", primary_group, "--endpoint-name", endpoint["name"],
                         subscription=subscription)
        for group in groups:
            for config in group.get("privateDnsZoneConfigs", []):
                zone_id = config["privateDnsZoneId"]
                selected[zone_id.lower()] = zone_id
    names: dict[str, str] = {}
    for zone_id in selected.values():
        zone_sub, _, name = coordinates(zone_id, "Microsoft.Network/privateDnsZones")
        az_json("network", "private-dns", "zone", "show", "--ids", zone_id, subscription=zone_sub)
        if name.lower() in names:
            raise ValueError(f"Two private DNS zones named {name} cannot both link to the same hub VNet.")
        names[name.lower()] = zone_id
    if not selected:
        raise ValueError("No primary private DNS zones found. Supply extra_private_dns_zone_ids or explicitly disable zone linking.")
    return sorted(selected.values(), key=str.lower)


def discover_targets(subscription: str, primary_group: str, vnet: dict,
                     apim_name: str | None = None) -> list[dict]:
    networks = [ipaddress.ip_network(prefix) for prefix in vnet["addressSpace"]["addressPrefixes"]]
    targets: dict[str, set[str]] = {}

    def add(host: str, addresses: list[str]) -> None:
        private_addresses = {address for address in addresses
                             if any(ipaddress.ip_address(address) in network for network in networks)}
        if host and private_addresses:
            if host.lower().endswith((".redis.azure.net", ".redis.cache.windows.net", ".redisenterprise.cache.azure.net")):
                utils.print_warning(f"{host}: Redis requires its service-specific port/client, not the notebook's HTTPS 443 check.")
                return
            targets.setdefault(host.lower().rstrip("."), set()).update(private_addresses)

    endpoints = az_json("network", "private-endpoint", "list", "--resource-group", primary_group,
                        subscription=subscription)
    for endpoint in endpoints:
        if endpoint["subnet"]["id"].rsplit("/subnets/", 1)[0].lower() != vnet["id"].lower():
            continue
        configs = endpoint.get("customDnsConfigs") or []
        if configs:
            for config in configs:
                add(config["fqdn"], config.get("ipAddresses") or [])
        else:
            for interface in endpoint.get("networkInterfaces", []):
                nic = az_json("network", "nic", "show", "--ids", interface["id"], subscription=subscription)
                for config in nic.get("ipConfigurations", []):
                    for host in (config.get("privateLinkConnectionProperties") or {}).get("fqdns") or []:
                        add(host, [config["privateIPAddress"]])
    if apim_name:
        apim = az_json("apim", "show", "--resource-group", primary_group, "--name", apim_name,
                       subscription=subscription)
        host = urlsplit(apim.get("gatewayUrl", "")).hostname
        if host and apim.get("virtualNetworkType") == "Internal":
            add(host, apim.get("privateIPAddresses") or [])
    result = [{"host": host, "expected_ips": sorted(addresses)} for host, addresses in sorted(targets.items())]
    if not result:
        raise ValueError("No private service targets discovered. Set validation_targets explicitly from primary endpoint DNS/NIC settings.")
    utils.print_ok(f"Discovered {len(result)} private HTTPS validation targets.", result)
    return result


def bicep_literal(value: Any) -> str:
    if isinstance(value, str):
        return "'" + value.replace("\\", "\\\\").replace("'", "\\'").replace("\r", "\\r").replace("\n", "\\n").replace("${", "\\${") + "'"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return "[\n" + "\n".join("  " + bicep_literal(item) for item in value) + "\n]"
    raise TypeError(f"Unsupported Bicep parameter type: {type(value).__name__}")


def write_parameters(template: Path, destination: Path, parameters: dict) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    relative = os.path.relpath(template, destination.parent).replace(os.sep, "/")
    source = f"using {bicep_literal(relative)}\n\n"
    source += "\n\n".join(f"param {name} = {bicep_literal(value)}" for name, value in parameters.items()) + "\n"
    destination.write_text(source, encoding="utf-8")
    return destination


def verify_azure_deployment(subscription: str, primary_vnet_id: str, outputs: dict) -> None:
    hub_id = outputs["hubVnetId"]["value"]
    gateway = az_json("network", "vnet-gateway", "show", "--ids", outputs["gatewayId"]["value"],
                      subscription=subscription)
    if gateway.get("provisioningState") != "Succeeded":
        raise RuntimeError("VPN Gateway provisioning has not succeeded.")
    if gateway["vpnClientConfiguration"]["vpnAuthenticationTypes"] != ["AAD"]:
        raise RuntimeError("Expected an Entra-only VPN Gateway.")
    if outputs["dnsResolverInboundIp"]["value"]:
        prefix = outputs["gatewayName"]["value"].removesuffix("-gateway")
        resolver_id = hub_id.rsplit("/virtualNetworks/", 1)[0] + f"/dnsResolvers/{prefix}-dns/inboundEndpoints/inbound"
        inbound = az_json("resource", "show", "--ids", resolver_id, "--api-version", "2022-07-01",
                          subscription=subscription)
        properties = inbound["properties"]
        if (properties.get("provisioningState") != "Succeeded"
                or properties["ipConfigurations"][0]["privateIpAddress"] != outputs["dnsResolverInboundIp"]["value"]):
            raise RuntimeError("DNS resolver inbound endpoint is not ready at its expected static IP.")
    primary_subscription, primary_group, primary_name = coordinates(primary_vnet_id, "Microsoft.Network/virtualNetworks")
    _, hub_group, hub_name = coordinates(hub_id, "Microsoft.Network/virtualNetworks")
    for scope, group, name, peering_name, remote, transit in (
        (subscription, hub_group, hub_name, outputs["hubPeeringName"]["value"], primary_vnet_id, True),
        (primary_subscription, primary_group, primary_name, outputs["primaryPeeringName"]["value"], hub_id, False),
    ):
        peering = az_json("network", "vnet", "peering", "show", "--resource-group", group,
                          "--vnet-name", name, "--name", peering_name, subscription=scope)
        if (peering.get("peeringState") != "Connected" or peering["remoteVirtualNetwork"]["id"].lower() != remote.lower()
                or not peering.get("allowVirtualNetworkAccess") or not peering.get("allowForwardedTraffic")
                or peering.get("allowGatewayTransit", False) != transit
                or peering.get("useRemoteGateways", False) != (not transit)):
            raise RuntimeError(f"Peering {peering_name} is not Connected with the expected gateway transit settings.")
    for zone_id in outputs["linkedPrivateDnsZoneIds"]["value"]:
        zone_sub, zone_group, name = coordinates(zone_id, "Microsoft.Network/privateDnsZones")
        link = az_json("network", "private-dns", "link", "vnet", "show", "--resource-group", zone_group,
                       "--zone-name", name, "--name", outputs["dnsLinkName"]["value"], subscription=zone_sub)
        if (link["virtualNetwork"]["id"].lower() != hub_id.lower() or link.get("registrationEnabled")
                or link.get("virtualNetworkLinkState") != "Completed"):
            raise RuntimeError(f"Private DNS link for {name} is not ready.")
    utils.print_ok("Azure gateway, both transit peerings and requested DNS links verified.")


def client_dns_server(outputs: dict, external_dns_server_ip: str | None = None) -> str:
    address = outputs["dnsResolverInboundIp"]["value"] or external_dns_server_ip
    require_values(dns_server_ip=address)
    if not isinstance(address, str) or not ipaddress.IPv4Address(address).is_private:
        raise ValueError("VPN client DNS requires the deployed private IPv4 resolver or an explicit private resolver.")
    return address


def customize_profile(source: bytes, resolver_ip: str, suffixes: list[str],
                      prefixes: list[str], *, profile_name: str | None = None) -> bytes:
    root = ET.fromstring(source)
    namespace = root.tag.partition("}")[0] + "}" if root.tag.startswith("{") else ""
    if namespace:
        ET.register_namespace("", namespace[1:-1])
    if profile_name is not None:
        name_node = root.find(f"{namespace}name")
        if name_node is None or not profile_name.strip():
            raise ValueError("A named Azure VPN profile is required to create an OS-specific connection.")
        name_node.text = profile_name
    config = root.find(f"{namespace}clientconfig")
    if config is None:
        config = ET.SubElement(root, f"{namespace}clientconfig")
    config.attrib.pop("{http://www.w3.org/2001/XMLSchema-instance}nil", None)
    for tag in ("dnsservers", "dnssuffixes", "includeroutes"):
        previous = config.find(f"{namespace}{tag}")
        if previous is not None:
            config.remove(previous)
    if resolver_ip:
        ipaddress.IPv4Address(resolver_ip)
        if suffixes:
            suffix_nodes = ET.SubElement(config, f"{namespace}dnssuffixes")
            for suffix in suffixes:
                ET.SubElement(suffix_nodes, f"{namespace}dnssuffix").text = "." + suffix.lstrip(".")
        servers = ET.SubElement(config, f"{namespace}dnsservers")
        ET.SubElement(servers, f"{namespace}dnsserver").text = resolver_ip
    routes = ET.SubElement(config, f"{namespace}includeroutes")
    for prefix in sorted(set(prefixes)):
        network = ipaddress.IPv4Network(prefix, strict=True)
        if network.prefixlen == 0:
            raise ValueError("This runbook uses split tunneling; default routes are not allowed.")
        route = ET.SubElement(routes, f"{namespace}route")
        ET.SubElement(route, f"{namespace}destination").text = str(network.network_address)
        ET.SubElement(route, f"{namespace}mask").text = str(network.prefixlen)
    config[:] = sorted(config, key=lambda node: node.tag)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def download_profiles(subscription: str, outputs: dict, directory: Path,
                      suffixes: list[str], prefixes: list[str]) -> list[Path]:
    url = az_json("network", "vnet-gateway", "vpn-client", "generate",
                  "--ids", outputs["gatewayId"]["value"], subscription=subscription, timeout=900)
    if not isinstance(url, str) or urlsplit(url).scheme != "https":
        raise RuntimeError("Azure CLI did not return an HTTPS VPN profile download URL.")
    directory.mkdir(parents=True, exist_ok=True)
    # Do not log or persist the temporary SAS download URL.
    archive_path = directory / "vpn-client.zip"
    with urlopen(url, timeout=120) as response:
        archive_path.write_bytes(response.read())
    profiles = []
    with zipfile.ZipFile(archive_path) as archive:
        candidates = [name for name in archive.namelist()
                      if Path(name).name.lower() in ("azurevpnconfig.xml", "azurevpnconfig_aad.xml")]
        if not candidates:
            raise RuntimeError("Generated package has no Azure VPN Client Entra XML profile.")
        for index, name in enumerate(candidates):
            original = archive.read(name)
            (directory / f"azurevpnconfig-original-{index}.xml").write_bytes(original)
            profile_root = ET.fromstring(original)
            name_node = next((node for node in profile_root if node.tag.rsplit("}", 1)[-1] == "name"), None)
            if name_node is None or not name_node.text:
                raise ValueError("Generated Azure VPN Client profile has no connection name.")
            resolver_ip = outputs["dnsResolverInboundIp"]["value"]
            for platform_suffixes, platform_name in ((suffixes, "windows"), ([], "macos")):
                target = directory / f"azurevpnconfig-{platform_name}-{index}.xml"
                display_name = f"{name_node.text} - {platform_name} DNS {resolver_ip}"
                target.write_bytes(customize_profile(
                    original, resolver_ip, platform_suffixes, prefixes, profile_name=display_name))
                profiles.append(target)
                utils.print_info(f"Import {target.name} and connect the entry named '{display_name}'.")
    return profiles


def validate_windows_dns_policy(resolver_ip: str, targets: list[dict]) -> None:
    if sys.platform != "win32":
        return
    policies = _run_json([
        "powershell", "-NoProfile", "-NonInteractive", "-Command",
        "$ErrorActionPreference = 'Stop'; ConvertTo-Json -Depth 5 -Compress -InputObject "
        "@(Get-DnsClientNrptPolicy -Effective | Select-Object Namespace,NameServers)",
    ])
    if not isinstance(policies, list):
        raise ValueError("Windows did not return the effective DNS policy list.")
    failures = []
    for target in targets:
        host = target["host"].lower().rstrip(".")
        matches = []
        for policy in policies:
            namespaces = policy.get("Namespace") or []
            if isinstance(namespaces, str):
                namespaces = [namespaces]
            servers = policy.get("NameServers") or []
            if isinstance(servers, str):
                servers = re.split(r"[\s,;]+", servers.strip())
            for namespace in namespaces:
                namespace = namespace.lower().rstrip(".") if namespace != "." else "."
                suffix = namespace.lstrip(".")
                if (namespace == "." or host == namespace
                        or namespace.startswith(".") and (host == suffix or host.endswith(namespace))):
                    score = (len(suffix), not namespace.startswith("."))
                    matches.append((score, set(servers)))
        best_score = max((score for score, _ in matches), default=None)
        if best_score is None or any(servers != {resolver_ip} for score, servers in matches if score == best_score):
            failures.append(target["host"])
    if failures:
        message = (
            f"{failures[0]}: effective Windows DNS/NRPT does not direct this hostname to {resolver_ip} "
            f"({len(failures)} target(s) affected). Import azurevpnconfig-windows-0.xml from the notebook's "
            "client directory, not the original XML/ZIP or macOS profile; disconnect and reconnect Azure VPN "
            "Client after importing. Check Get-DnsClientNrptPolicy -Effective. If a managed policy overrides "
            "the VPN rule, ask your network administrator; this notebook will not alter corporate DNS rules."
        )
        utils.print_error(message)
        raise RuntimeError(message)
    utils.print_ok(f"Effective Windows DNS/NRPT directs all {len(targets)} target(s) to {resolver_ip}.")


def validate_targets(targets: list[dict]) -> list[dict]:
    if not targets:
        raise ValueError("Supply at least one private endpoint FQDN and its expected private IPs.")
    results = []
    for target in targets:
        host = target["host"]
        expected = {str(ipaddress.ip_address(value)) for value in target["expected_ips"]}
        if not expected or any(not ipaddress.ip_address(value).is_private for value in expected):
            raise ValueError(f"{host}: expected_ips must contain private addresses.")
        try:
            actual = {entry[4][0] for entry in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)}
        except socket.gaierror as error:
            message = (
                f"{host}: OS DNS could not resolve the service name ({error}). A successful direct resolver "
                "query does not prove application DNS is configured. Import the generated profile for this OS, "
                "then disconnect and reconnect Azure VPN Client. On Windows check Get-DnsClientNrptPolicy -Effective; "
                "on macOS check scutil --dns. No direct-IP or public-DNS fallback will be used."
            )
            utils.print_error(message)
            raise RuntimeError(message) from error
        if not actual or not actual.issubset(expected):
            raise RuntimeError(f"{host}: OS resolved {sorted(actual)}, expected only {sorted(expected)}. Check VPN DNS/NRPT/DoH.")
        # Connect to the actual resolved private addresses, preserving the public hostname for TLS/SNI.
        for address in actual:
            with socket.create_connection((address, 443), timeout=10) as connection:
                with ssl.create_default_context().wrap_socket(connection, server_hostname=host) as tls:
                    results.append({"host": host, "ip": address, "tls": tls.version()})
        utils.print_ok(f"{host}: expected private DNS and trusted TLS on TCP 443 verified.")
    return results


def validate_resolver(resolver_ip: str, targets: list[dict]) -> None:
    executable = shutil.which("nslookup")
    if not executable:
        raise RuntimeError("Install the OS DNS diagnostic tools (nslookup) before running direct DNS checks.")
    for target in targets:
        command = [executable, target["host"], resolver_ip]
        result = subprocess.run(command, capture_output=True, text=True, timeout=30, check=False)
        returned = set(re.findall(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])", result.stdout))
        returned.discard(resolver_ip)
        if result.returncode or not returned.intersection(target["expected_ips"]):
            utils.print_error(result.stdout + result.stderr)
            raise RuntimeError(f"Direct DNS check failed for {target['host']} via {resolver_ip}.")
    utils.print_ok("Direct queries to the VPN DNS resolver returned expected private addresses.")


def cleanup(subscription: str, primary_vnet_id: str, outputs: dict, confirmation: str) -> None:
    group_id = outputs["vpnResourceGroupId"]["value"]
    group = group_id.rstrip("/").rsplit("/", 1)[-1]
    _, primary_group, _ = coordinates(primary_vnet_id, "Microsoft.Network/virtualNetworks")
    if confirmation != group or group.lower() == primary_group.lower():
        raise ValueError("Cleanup confirmation must equal the dedicated VPN resource group name.")
    if not check_group(subscription, group, primary_vnet_id):
        raise ValueError("VPN resource group is missing; inspect external links manually.")
    resources = az_json("resource", "list", "--resource-group", group, subscription=subscription)
    if any(not _owned_by_primary_vnet(resource.get("tags"), primary_vnet_id) for resource in resources):
        raise ValueError("VPN resource group contains unowned resources. Review them before deleting the group.")
    hub_id = outputs["hubVnetId"]["value"]
    for zone_id in outputs["linkedPrivateDnsZoneIds"]["value"]:
        zone_sub, zone_group, name = coordinates(zone_id, "Microsoft.Network/privateDnsZones")
        links = az_json("network", "private-dns", "link", "vnet", "list",
                        "--resource-group", zone_group, "--zone-name", name, subscription=zone_sub)
        matches = [link for link in links if link["name"] == outputs["dnsLinkName"]["value"]]
        for link in matches:
            if (link["virtualNetwork"]["id"].lower() != hub_id.lower()
                    or (link.get("tags") or {}).get("managed-by") != OWNER):
                raise ValueError("Refusing to delete an unowned DNS link.")
            az_json("network", "private-dns", "link", "vnet", "delete", "--resource-group", zone_group,
                    "--zone-name", name, "--name", link["name"], "--yes", subscription=zone_sub,
                    expect_json=False)
    primary_sub, primary_group, primary_name = coordinates(primary_vnet_id, "Microsoft.Network/virtualNetworks")
    peerings = az_json("network", "vnet", "peering", "list", "--resource-group", primary_group,
                       "--vnet-name", primary_name, subscription=primary_sub)
    for peering in peerings:
        if peering["name"] == outputs["primaryPeeringName"]["value"]:
            if peering["remoteVirtualNetwork"]["id"].lower() != hub_id.lower():
                raise ValueError("Refusing to delete a peering to a different network.")
            az_json("network", "vnet", "peering", "delete", "--resource-group", primary_group,
                    "--vnet-name", primary_name, "--name", peering["name"], subscription=primary_sub,
                    expect_json=False)
    az_json("group", "delete", "--name", group, "--yes", subscription=subscription, timeout=7200,
            expect_json=False)
    if az_json("group", "exists", "--name", group, subscription=subscription):
        raise RuntimeError("VPN resource group still exists after deletion; inspect Azure deployment operations.")
    utils.print_ok("Dedicated VPN resource group and its external links removed; primary resources preserved.")
