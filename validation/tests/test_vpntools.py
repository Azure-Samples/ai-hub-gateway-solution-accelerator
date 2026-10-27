"""Offline tests: no Azure deployment, sign-in or network connections."""

import contextlib
import io
import json
from pathlib import Path
import socket
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))
import utils
import vpntools as vpn

PRIMARY = "/subscriptions/sub/resourceGroups/primary/providers/Microsoft.Network/virtualNetworks/primary"
HUB = "/subscriptions/sub/resourceGroups/vpn/providers/Microsoft.Network/virtualNetworks/citadel-vpn-vnet"
ZONE = "/subscriptions/sub/resourceGroups/dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
NOTEBOOK = ROOT / "validation-local" / "citadel-developer-vpn-validation.ipynb"


def vnet():
    return {"id": PRIMARY, "name": "primary", "location": "region", "addressSpace": {
        "addressPrefixes": ["10.170.0.0/24"]}, "virtualNetworkPeerings": [], "subnets": []}


class VpnToolsTests(unittest.TestCase):
    def setUp(self):
        self.console = contextlib.redirect_stdout(io.StringIO())
        self.console.__enter__()
        self.addCleanup(self.console.__exit__, None, None, None)

    def test_address_plan_matches_bicep_without_materializing_large_subnets(self):
        result = vpn.validate_networks("10.171.0.0/24", "172.30.240.0/24",
                                       ["10.170.0.0/24"], ["192.168.10.0/24"])
        self.assertEqual(result, {"gatewaySubnet": "10.171.0.0/27",
                                 "resolverSubnet": "10.171.0.32/28", "resolverIp": "10.171.0.37"})
        self.assertEqual(vpn.validate_networks("10.0.0.0/8", "172.30.240.0/24",
                                              [], ["192.168.1.0/24"])["resolverIp"], "10.0.0.37")

    def test_network_conflicts_and_invalid_ranges_are_rejected(self):
        cases = [
            ("10.170.0.0/24", "172.30.240.0/24", ["10.170.0.0/24"], ["192.168.0.0/24"]),
            ("10.171.0.0/24", "10.171.0.0/25", [], ["192.168.0.0/24"]),
            ("10.171.0.0/24", "172.30.240.0/24", [], ["10.0.0.0/8"]),
            ("10.171.0.0/24", "172.30.240.0/24", ["172.30.0.0/16"], ["192.168.0.0/24"]),
            ("10.171.0.0/27", "172.30.240.0/24", [], ["192.168.0.0/24"]),
            ("8.8.8.0/24", "172.30.240.0/24", [], ["192.168.0.0/24"]),
            ("10.171.0.1/24", "172.30.240.0/24", [], ["192.168.0.0/24"]),
            ("10.171.0.0/24", "172.30.240.0/24", [], ["REPLACE"]),
            ("10.171.0.0/24", "172.30.240.0/24", [], []),
        ]
        for case in cases:
            with self.subTest(case=case), self.assertRaises(ValueError):
                vpn.validate_networks(*case)

    def test_invalid_resource_id_is_rejected(self):
        self.assertEqual(vpn.coordinates(PRIMARY, "Microsoft.Network/virtualNetworks"), ("sub", "primary", "primary"))
        with self.assertRaises(ValueError):
            vpn.coordinates("REPLACE", "Microsoft.Network/virtualNetworks")

    @patch.object(vpn, "_run_json")
    def test_azd_defaults_are_loaded_once_and_vpn_names_follow_primary_group(self, run):
        run.return_value = {"AZURE_SUBSCRIPTION_ID": "sub", "AZURE_RESOURCE_GROUP": "rg-primary",
                            "AZURE_LOCATION": "region", "APIM_NAME": "apim"}
        result = vpn.notebook_defaults({})
        run.assert_called_once_with(["azd", "env", "get-values", "--output", "json"])
        self.assertEqual(result["expected_subscription_id"], "sub")
        self.assertEqual(result["governance_hub_resource_group"], "rg-primary")
        self.assertEqual(result["location"], "region")
        self.assertEqual(result["apim_name"], "apim")
        self.assertEqual(result["vpn_resource_group"], "rg-primary-vpn")
        self.assertEqual(result["resource_prefix"], "citadel-vpn")
        self.assertIsNone(result["primary_vnet_id"])

    @patch.object(vpn, "_run_json")
    def test_explicit_coordinates_and_vpn_overrides_win_over_active_azd(self, run):
        run.return_value = {"AZURE_SUBSCRIPTION_ID": "env-sub", "AZURE_RESOURCE_GROUP": "env-group",
                            "AZURE_LOCATION": "env-region", "VPN_RESOURCE_GROUP": "env-vpn",
                            "PRIMARY_VNET_ID": PRIMARY, "VPN_RESOURCE_PREFIX": "env-prefix"}
        overrides = {"expected_subscription_id": "explicit-sub", "governance_hub_resource_group": "explicit-group",
                     "location": "explicit-region", "vpn_resource_group": "explicit-vpn",
                     "resource_prefix": "explicit-prefix"}
        result = vpn.notebook_defaults(overrides)
        self.assertTrue(all(result[key] == value for key, value in overrides.items()))
        self.assertEqual(result["primary_vnet_id"], PRIMARY)

    @patch.object(vpn, "_run_json")
    def test_manual_defaults_do_not_read_azd_and_long_names_remain_unique(self, run):
        overrides = {"expected_subscription_id": "sub", "governance_hub_resource_group": "a" * 90}
        first = vpn.notebook_defaults(overrides, from_azd=False)
        second = vpn.notebook_defaults({**overrides, "governance_hub_resource_group": "a" * 89 + "b"},
                                       from_azd=False)
        run.assert_not_called()
        self.assertLessEqual(len(first["vpn_resource_group"]), 90)
        self.assertNotEqual(first["vpn_resource_group"], second["vpn_resource_group"])

    @patch.object(vpn, "_run_json")
    def test_bad_or_missing_azd_settings_do_not_silently_use_the_cli_account(self, run):
        for snapshot in ([], {}, {"AZURE_SUBSCRIPTION_ID": "sub", "AZURE_RESOURCE_GROUP": "REPLACE"}):
            with self.subTest(snapshot=snapshot), self.assertRaises(ValueError):
                run.return_value = snapshot
                vpn.notebook_defaults({})
        run.side_effect = RuntimeError("azd environment unavailable")
        with self.assertRaisesRegex(RuntimeError, "azd environment unavailable"):
            vpn.notebook_defaults({})

    @patch.object(vpn, "_run_json", return_value={"AZURE_SUBSCRIPTION_ID": "sub", "AZURE_RESOURCE_GROUP": "primary"})
    def test_invalid_explicit_override_is_not_replaced_with_an_environment_default(self, _run):
        with self.assertRaisesRegex(ValueError, "string override"):
            vpn.notebook_defaults({"vpn_resource_group": 123})

    @patch.object(vpn.sys, "platform", "win32")
    @patch.object(vpn, "_run_json")
    def test_windows_routes_include_corporate_ranges_but_not_internet_or_loopback(self, run):
        run.return_value = ["0.0.0.0/0", "127.0.0.0/8", "169.254.0.0/16", "224.0.0.0/4",
                            "192.168.1.0/24", "192.168.1.10/32", "10.20.0.0/16", "10.20.0.0/16"]
        self.assertEqual(vpn.discover_local_networks(), ["10.20.0.0/16", "192.168.1.0/24", "192.168.1.10/32"])
        self.assertIn("Get-NetRoute", run.call_args.args[0][-1])

    @patch.object(vpn.sys, "platform", "darwin")
    @patch.object(vpn.subprocess, "run")
    def test_macos_route_table_normalizes_abbreviated_networks(self, run):
        run.return_value = SimpleNamespace(returncode=0, stderr="", stdout=(
            "Routing tables\nDestination Gateway Flags Netif\n"
            "default 192.168.1.1 UGSc en0\n10.20/16 link#3 UCS utun2\n"
            "192.168.1 link#4 UCS en0\n127 127.0.0.1 UCS lo0\n"))
        self.assertEqual(vpn.discover_local_networks(), ["10.20.0.0/16", "192.168.1.0/24"])

    @patch.object(vpn.sys, "platform", "linux")
    @patch.object(vpn, "_run_json")
    def test_linux_can_prepare_configuration_without_claiming_entra_client_support(self, run):
        run.return_value = [{"dst": "default"}, {"dst": "172.20.0.0/16"}, {"dst": "127.0.0.0/8"}]
        self.assertEqual(vpn.discover_local_networks(), ["172.20.0.0/16"])

    @patch.object(vpn.sys, "platform", "win32")
    @patch.object(vpn, "_run_json")
    def test_route_discovery_failure_is_not_an_empty_success(self, run):
        run.return_value = []
        with self.assertRaisesRegex(ValueError, "No private IPv4"):
            vpn.discover_local_networks()
        run.side_effect = RuntimeError("route access denied")
        with self.assertRaisesRegex(RuntimeError, "route access denied"):
            vpn.discover_local_networks()

    @patch.object(vpn, "az_json")
    def test_ownership_check_never_adopts_an_existing_unowned_group(self, az):
        az.side_effect = [True, {"tags": {}}]
        with self.assertRaisesRegex(ValueError, "not owned"):
            vpn.check_group("sub", "vpn", PRIMARY)

    @patch.object(vpn, "az_json")
    def test_ownership_check_rejects_an_unresolved_primary_before_querying_azure(self, az):
        with self.assertRaisesRegex(ValueError, "primary_vnet_id"):
            vpn.check_group("sub", "vpn", None)
        az.assert_not_called()

    @patch.object(vpn, "az_json")
    def test_ownership_check_rejects_null_or_nonstring_primary_tags(self, az):
        for value in (None, 123, ""):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "not owned"):
                az.side_effect = [True, {"tags": {"managed-by": vpn.OWNER, "primary-vnet-id": value}}]
                vpn.check_group("sub", "vpn", PRIMARY)

    @patch.object(vpn, "check_group", return_value=False)
    @patch.object(vpn, "az_json")
    def test_transit_conflicts_and_separate_rg_are_enforced(self, az, _group):
        current = vnet()
        current["virtualNetworkPeerings"] = [{"name": "existing", "useRemoteGateways": True,
                                             "remoteVirtualNetwork": {"id": HUB.replace("/vpn/", "/other/")}}]
        az.return_value = current
        with self.assertRaisesRegex(ValueError, "another remote gateway"):
            vpn.inspect_primary("sub", "primary", PRIMARY, "vpn", "citadel-vpn")
        with self.assertRaisesRegex(ValueError, "separate VPN"):
            vpn.inspect_primary("sub", "primary", PRIMARY, "primary", "citadel-vpn")
        for name in ("..", "../outside", "vpn/name"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                vpn.inspect_primary("sub", "primary", PRIMARY, name, "citadel-vpn")

    @patch.object(vpn, "check_group", return_value=True)
    @patch.object(vpn, "az_json")
    def test_rerun_ignores_only_its_own_hub_when_checking_remote_prefixes(self, az, _group):
        current = vnet()
        current["virtualNetworkPeerings"] = [{"name": "citadel-vpn-to-vpn", "useRemoteGateways": True,
                                             "remoteVirtualNetwork": {"id": HUB}}]
        az.return_value = current
        actual, prefixes = vpn.inspect_primary("sub", "primary", PRIMARY, "vpn", "citadel-vpn")
        self.assertEqual(actual, current)
        self.assertEqual(prefixes, ["10.170.0.0/24"])
        self.assertEqual(az.call_count, 1)

    @patch.object(vpn, "check_group", return_value=False)
    @patch.object(vpn, "az_json")
    def test_byo_primary_vnet_is_inferred_from_azd_apim_subnet(self, az, _group):
        current = vnet()
        current["id"] = PRIMARY.replace("/primary/", "/network/", 1)
        az.side_effect = [{"virtualNetworkConfiguration": {
            "subnetResourceId": current["id"] + "/subnets/apim"}}, current]
        actual, _ = vpn.inspect_primary("sub", "primary", None, "vpn", "citadel-vpn", "apim")
        self.assertEqual(actual["id"], current["id"])
        self.assertEqual(az.call_args_list[0].args[:2], ("apim", "show"))

    @patch.object(vpn, "check_group", return_value=False)
    @patch.object(vpn, "az_json")
    def test_primary_endpoint_vnet_is_preferred_over_guessing_from_rg_vnets(self, az, _group):
        current = vnet()
        az.side_effect = [[{"subnet": {"id": PRIMARY + "/subnets/endpoints"}}], current]
        actual, _ = vpn.inspect_primary("sub", "primary", None, "vpn", "citadel-vpn")
        self.assertEqual(actual["id"], PRIMARY)
        self.assertEqual(az.call_args_list[0].args[:3], ("network", "private-endpoint", "list"))

    @patch.object(vpn, "az_json")
    def test_ambiguous_endpoint_networks_are_not_guessed(self, az):
        az.return_value = [{"subnet": {"id": PRIMARY + "/subnets/endpoints"}},
                           {"subnet": {"id": HUB + "/subnets/endpoints"}}]
        with self.assertRaisesRegex(ValueError, "span multiple VNets"):
            vpn.inspect_primary("sub", "primary", None, "vpn", "citadel-vpn")

    @patch.object(vpn, "az_json")
    def test_validation_targets_come_from_primary_endpoint_dns_nics_and_apim(self, az):
        endpoint = {"subnet": {"id": PRIMARY + "/subnets/endpoints"},
                    "customDnsConfigs": [{"fqdn": "storage.blob.core.windows.net",
                                          "ipAddresses": ["10.170.0.70"]}]}
        nic_endpoint = {"subnet": endpoint["subnet"], "networkInterfaces": [{"id": "/nic"}]}
        other_endpoint = {"subnet": {"id": HUB + "/subnets/endpoints"},
                          "customDnsConfigs": [{"fqdn": "unrelated.example", "ipAddresses": ["10.171.0.70"]}]}
        az.side_effect = [
            [endpoint, nic_endpoint, other_endpoint],
            {"ipConfigurations": [{"privateIPAddress": "10.170.0.71",
                                    "privateLinkConnectionProperties": {"fqdns": ["vault.vault.azure.net"]}}]},
            {"gatewayUrl": "https://gateway.azure-api.net", "privateIPAddresses": ["10.170.0.10"],
             "virtualNetworkType": "Internal"},
        ]
        targets = vpn.discover_targets("sub", "primary", vnet(), "apim")
        self.assertEqual({target["host"] for target in targets},
                         {"storage.blob.core.windows.net", "vault.vault.azure.net", "gateway.azure-api.net"})
        self.assertTrue(all(target["expected_ips"] for target in targets))

    @patch.object(vpn, "az_json")
    def test_external_apim_is_not_falsely_treated_as_an_internal_gateway(self, az):
        az.side_effect = [[], {"gatewayUrl": "https://gateway.azure-api.net",
                              "privateIPAddresses": ["10.170.0.10"], "virtualNetworkType": "External"}]
        with self.assertRaisesRegex(ValueError, "No private service targets"):
            vpn.discover_targets("sub", "primary", vnet(), "apim")

    @patch.object(vpn, "az_json", return_value=[])
    def test_missing_private_targets_require_an_explicit_override(self, _az):
        with self.assertRaisesRegex(ValueError, "No private service targets"):
            vpn.discover_targets("sub", "primary", vnet())

    @patch.object(vpn, "az_json")
    def test_auto_https_targets_do_not_probe_redis_on_the_wrong_port(self, az):
        az.return_value = [{"subnet": {"id": PRIMARY + "/subnets/endpoints"}, "customDnsConfigs": [
            {"fqdn": "cache.region.redis.azure.net", "ipAddresses": ["10.170.0.80"]},
            {"fqdn": "storage.blob.core.windows.net", "ipAddresses": ["10.170.0.70"]},
        ]}]
        targets = vpn.discover_targets("sub", "primary", vnet())
        self.assertEqual(targets, [{"host": "storage.blob.core.windows.net", "expected_ips": ["10.170.0.70"]}])

    @patch.object(vpn, "check_group", return_value=False)
    @patch.object(vpn, "az_json")
    def test_gateway_subnet_and_disabled_route_propagation_block_transit(self, az, _group):
        current = vnet()
        current["subnets"] = [{"name": "GatewaySubnet"}]
        az.return_value = current
        with self.assertRaisesRegex(ValueError, "gateway/route-server"):
            vpn.inspect_primary("sub", "primary", PRIMARY, "vpn", "citadel-vpn")
        current["subnets"] = [{"name": "apim", "routeTable": {"id": "/route/table"}}]
        az.side_effect = [current, {"name": "apim-routes", "disableBgpRoutePropagation": True}]
        with self.assertRaisesRegex(ValueError, "propagation is disabled"):
            vpn.inspect_primary("sub", "primary", PRIMARY, "vpn", "citadel-vpn")

    @patch.object(vpn, "az_json")
    def test_dns_discovery_includes_owned_linked_endpoint_and_explicit_external_zones(self, az):
        owned = ZONE.replace("/dns/", "/primary/")
        linked = ZONE.replace("blob", "file")
        external = ZONE.replace("/sub/", "/external/").replace("blob", "queue")
        explicit = ZONE.replace("/sub/", "/external/").replace("blob", "table")
        az.side_effect = [
            [{"id": owned}, {"id": linked}],
            [],
            [{"virtualNetwork": {"id": PRIMARY.upper()}}],
            [{"name": "endpoint"}],
            [{"privateDnsZoneConfigs": [{"privateDnsZoneId": external}]}],
            {}, {}, {}, {},
        ]
        zones = vpn.discover_zones("sub", "primary", vnet(), [explicit])
        self.assertEqual(set(zones), {owned, linked, external, explicit})
        endpoint_command = az.call_args_list[4].args
        self.assertIn("--endpoint-name", endpoint_command)

    @patch.object(vpn, "az_json")
    def test_dns_duplicate_names_and_discovery_errors_are_not_hidden(self, az):
        az.side_effect = [[], [], {}, {}]
        with self.assertRaisesRegex(ValueError, "cannot both link"):
            vpn.discover_zones("sub", "primary", vnet(), [ZONE, ZONE.replace("/dns/", "/other/")])
        az.side_effect = RuntimeError("Forbidden")
        with self.assertRaisesRegex(RuntimeError, "Forbidden"):
            vpn.discover_zones("sub", "primary", vnet(), [])

    def test_namespaced_profile_preserves_auth_removes_nil_and_adds_private_routes(self):
        original = b'<AzVpnProfile xmlns="urn:azure" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><clientconfig i:nil="true"/><clientauth><aad>preserved</aad></clientauth></AzVpnProfile>'
        modified = vpn.customize_profile(original, "10.171.0.36", [".blob.core.windows.net"],
                                         ["10.171.0.0/24", "10.170.0.0/24"])
        root = ET.fromstring(modified)
        ns = {"a": "urn:azure"}
        self.assertEqual(root.findtext("a:clientauth/a:aad", namespaces=ns), "preserved")
        self.assertFalse(root.find("a:clientconfig", ns).attrib)
        self.assertEqual(root.findtext(".//a:dnsserver", namespaces=ns), "10.171.0.36")
        self.assertEqual(root.findtext(".//a:dnssuffix", namespaces=ns), ".blob.core.windows.net")
        self.assertEqual(len(root.findall(".//a:route", ns)), 2)
        self.assertEqual(vpn.customize_profile(modified, "10.171.0.36", [".blob.core.windows.net"],
                                              ["10.171.0.0/24", "10.170.0.0/24"]), modified)
        mac = ET.fromstring(vpn.customize_profile(original, "10.171.0.36", [], ["10.170.0.0/24"]))
        self.assertIsNone(mac.find(".//a:dnssuffixes", ns))
        with self.assertRaisesRegex(ValueError, "split tunneling"):
            vpn.customize_profile(original, "10.171.0.36", [], ["0.0.0.0/0"])

    def test_parameters_are_bicep_not_json_and_escape_interpolation(self):
        self.assertEqual(vpn.bicep_literal("x'${value}"), "'x\\'\\${value}'")
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "main.bicepparam"
            vpn.write_parameters(Path(directory) / "infra" / "main.bicep",
                                 destination, {"deployDnsResolver": True, "privateDnsZoneIds": [ZONE]})
            source = destination.read_text()
            self.assertIn("param deployDnsResolver = true", source)
            self.assertIn("param privateDnsZoneIds = [", source)

    @patch.object(vpn, "az_json", return_value="https://profiles.example/package.zip?sig=not-logged")
    @patch.object(vpn, "urlopen")
    def test_profile_package_download_generates_both_platforms_without_extracting_paths(self, open_url, az):
        archive_bytes = io.BytesIO()
        with zipfile.ZipFile(archive_bytes, "w") as archive:
            archive.writestr("AzureVPN/azurevpnconfig_aad.xml",
                             '<AzVpnProfile><clientconfig/><clientauth>preserved</clientauth><name>fixture-vnet</name></AzVpnProfile>')
            archive.writestr("../../unrelated.txt", "must not be extracted")
        response = MagicMock()
        response.read.return_value = archive_bytes.getvalue()
        open_url.return_value.__enter__.return_value = response
        outputs = {"gatewayId": {"value": "/gateway"}, "dnsResolverInboundIp": {"value": "10.171.0.36"}}
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            profiles = vpn.download_profiles("sub", outputs, directory, [".blob.core.windows.net"], ["10.170.0.0/24"])
            self.assertEqual(len(profiles), 2)
            self.assertTrue(all(path.is_file() for path in profiles))
            self.assertIsNotNone(ET.parse(profiles[0]).find(".//dnssuffixes"))
            self.assertIsNone(ET.parse(profiles[1]).find(".//dnssuffixes"))
            self.assertEqual(ET.parse(profiles[0]).findtext(".//clientauth"), "preserved")
            self.assertEqual(ET.parse(profiles[0]).findtext("name"), "fixture-vnet - windows DNS 10.171.0.36")
            self.assertEqual(ET.parse(profiles[1]).findtext("name"), "fixture-vnet - macos DNS 10.171.0.36")
            self.assertEqual(len(list(directory.iterdir())), 4)
        self.assertIn("vpn-client", az.call_args.args)
        self.assertEqual(az.call_args.kwargs["subscription"], "sub")

    @patch.object(vpn, "az_json", return_value="http://profiles.example/package.zip")
    @patch.object(vpn, "urlopen")
    def test_non_https_profile_download_is_rejected(self, open_url, _az):
        with self.assertRaisesRegex(RuntimeError, "HTTPS"):
            vpn.download_profiles("sub", {"gatewayId": {"value": "/gateway"}}, Path("unused"), [], [])
        open_url.assert_not_called()

    @patch.object(vpn.shutil, "which", return_value="az")
    @patch.object(vpn.subprocess, "run")
    def test_cli_fails_closed_and_supports_successful_empty_delete_responses(self, run, _which):
        run.return_value = SimpleNamespace(returncode=0, stdout="", stderr="")
        self.assertIsNone(vpn.az_json("group", "delete", expect_json=False))
        with self.assertRaisesRegex(RuntimeError, "Expected Azure CLI JSON"):
            vpn.az_json("group", "show")
        run.return_value = SimpleNamespace(returncode=1, stdout="", stderr="Forbidden")
        with self.assertRaisesRegex(RuntimeError, "Azure CLI failed"):
            vpn.az_json("group", "show")

    def test_client_dns_uses_deployed_address_not_a_preflight_prediction(self):
        outputs = {"dnsResolverInboundIp": {"value": "10.171.0.37"}}
        self.assertEqual(vpn.client_dns_server(outputs, "10.171.0.36"), "10.171.0.37")
        self.assertEqual(vpn.client_dns_server({"dnsResolverInboundIp": {"value": ""}}, "10.2.0.4"), "10.2.0.4")
        with self.assertRaises(ValueError):
            vpn.client_dns_server({"dnsResolverInboundIp": {"value": ""}})

    @patch.object(vpn.socket, "getaddrinfo", side_effect=socket.gaierror(11001, "getaddrinfo failed"))
    @patch.object(vpn.socket, "create_connection")
    def test_os_dns_failure_identifies_the_hostname_and_client_fix_without_bypassing_dns(self, connect, _resolve):
        with self.assertRaisesRegex(RuntimeError, r"service\.example.*OS DNS.*reconnect") as error:
            vpn.validate_targets([{"host": "service.example", "expected_ips": ["10.170.0.70"]}])
        self.assertIsInstance(error.exception.__cause__, socket.gaierror)
        connect.assert_not_called()

    @patch.object(vpn.sys, "platform", "win32")
    @patch.object(vpn, "_run_json")
    def test_windows_dns_policy_requires_effective_rules_for_each_target(self, run):
        targets = [{"host": "resource.cognitiveservices.azure.com", "expected_ips": ["10.170.0.70"]}]
        run.return_value = [{"Namespace": ["https://gateway.vpn.azure.com"], "NameServers": None}]
        with self.assertRaisesRegex(RuntimeError, r"resource\.cognitiveservices\.azure\.com.*NRPT"):
            vpn.validate_windows_dns_policy("10.171.0.37", targets)
        run.return_value = [{"Namespace": [".cognitiveservices.azure.com"], "NameServers": ["10.171.0.37"]}]
        vpn.validate_windows_dns_policy("10.171.0.37", targets)
        self.assertIn("Get-DnsClientNrptPolicy -Effective", run.call_args.args[0][-1])

    @patch.object(vpn.sys, "platform", "win32")
    @patch.object(vpn, "_run_json")
    def test_more_specific_managed_dns_rule_cannot_be_hidden_by_a_matching_vpn_suffix(self, run):
        targets = [{"host": "resource.services.ai.azure.com", "expected_ips": ["10.170.0.70"]}]
        run.return_value = [
            {"Namespace": [".azure.com"], "NameServers": ["10.171.0.37"]},
            {"Namespace": ["resource.services.ai.azure.com"], "NameServers": ["192.168.1.1"]},
        ]
        with self.assertRaisesRegex(RuntimeError, "NRPT"):
            vpn.validate_windows_dns_policy("10.171.0.37", targets)

    @patch.object(vpn.sys, "platform", "darwin")
    @patch.object(vpn, "_run_json")
    def test_macos_does_not_run_windows_nrpt_inspection(self, run):
        vpn.validate_windows_dns_policy("10.171.0.37", [])
        run.assert_not_called()

    @patch.object(vpn.socket, "getaddrinfo", return_value=[(socket.AF_INET, 1, 6, "", ("20.1.1.1", 443))])
    @patch.object(vpn.socket, "create_connection")
    def test_public_dns_result_is_rejected_before_connection(self, connect, _resolve):
        with self.assertRaisesRegex(RuntimeError, "OS resolved"):
            vpn.validate_targets([{"host": "service.example", "expected_ips": ["10.170.0.70"]}])
        connect.assert_not_called()

    @patch.object(vpn.ssl, "create_default_context")
    @patch.object(vpn.socket, "create_connection")
    @patch.object(vpn.socket, "getaddrinfo", return_value=[(socket.AF_INET, 1, 6, "", ("10.170.0.70", 443))])
    def test_tls_validates_the_original_hostname_over_the_expected_private_address(self, _resolve, connect, ssl_context):
        ssl_context.return_value.wrap_socket.return_value.__enter__.return_value.version.return_value = "TLSv1.3"
        result = vpn.validate_targets([{"host": "service.example", "expected_ips": ["10.170.0.70"]}])
        connect.assert_called_once_with(("10.170.0.70", 443), timeout=10)
        self.assertEqual(ssl_context.return_value.wrap_socket.call_args.kwargs["server_hostname"], "service.example")
        self.assertEqual(result[0]["ip"], "10.170.0.70")

    @patch.object(vpn.shutil, "which", return_value="nslookup")
    @patch.object(vpn.subprocess, "run")
    def test_direct_dns_requires_expected_private_answer_not_just_resolver_address(self, run, _which):
        target = [{"host": "service.example", "expected_ips": ["10.170.0.70"]}]
        run.return_value = SimpleNamespace(returncode=0, stdout="Server: resolver\nAddress: 10.171.0.36\nAddress: 10.170.0.70", stderr="")
        vpn.validate_resolver("10.171.0.36", target)
        run.return_value.stdout = "Server: resolver\nAddress: 10.171.0.36\nAddress: 20.1.1.1"
        with self.assertRaisesRegex(RuntimeError, "Direct DNS check failed"):
            vpn.validate_resolver("10.171.0.36", target)

    @patch.object(vpn, "az_json")
    def test_azure_verification_requires_both_transit_peerings_and_completed_dns_links(self, az):
        outputs = {
            "hubVnetId": {"value": HUB}, "gatewayId": {"value": "/gateway"},
            "gatewayName": {"value": "citadel-vpn-gateway"},
            "dnsResolverInboundIp": {"value": "10.171.0.36"},
            "hubPeeringName": {"value": "citadel-vpn-to-primary"},
            "primaryPeeringName": {"value": "citadel-vpn-to-vpn"},
            "linkedPrivateDnsZoneIds": {"value": [ZONE]}, "dnsLinkName": {"value": "owned"},
        }
        gateway = {"provisioningState": "Succeeded",
                   "vpnClientConfiguration": {"vpnAuthenticationTypes": ["AAD"]}}
        inbound = {"properties": {"provisioningState": "Succeeded",
                                 "ipConfigurations": [{"privateIpAddress": "10.171.0.36"}]}}
        hub_peering = {"peeringState": "Connected", "remoteVirtualNetwork": {"id": PRIMARY},
                       "allowVirtualNetworkAccess": True, "allowForwardedTraffic": True,
                       "allowGatewayTransit": True, "useRemoteGateways": False}
        primary_peering = {**hub_peering, "remoteVirtualNetwork": {"id": HUB},
                           "allowGatewayTransit": False, "useRemoteGateways": True}
        link = {"virtualNetwork": {"id": HUB}, "registrationEnabled": False,
                "virtualNetworkLinkState": "Completed"}
        az.side_effect = [gateway, inbound, hub_peering, primary_peering, link]
        vpn.verify_azure_deployment("sub", PRIMARY, outputs)
        primary_peering["useRemoteGateways"] = False
        az.side_effect = [gateway, inbound, hub_peering, primary_peering]
        with self.assertRaisesRegex(RuntimeError, "expected gateway transit"):
            vpn.verify_azure_deployment("sub", PRIMARY, outputs)

    @patch.object(vpn, "check_group", return_value=True)
    @patch.object(vpn, "az_json")
    def test_cleanup_removes_external_links_before_dedicated_group_and_checks_deletion(self, az, _group):
        outputs = {
            "vpnResourceGroupId": {"value": "/subscriptions/sub/resourceGroups/vpn"},
            "hubVnetId": {"value": HUB}, "linkedPrivateDnsZoneIds": {"value": [ZONE]},
            "dnsLinkName": {"value": "owned"}, "primaryPeeringName": {"value": "owned-peer"},
        }
        tags = {"managed-by": vpn.OWNER, "primary-vnet-id": PRIMARY}
        az.side_effect = [[{"tags": tags}],
                          [{"name": "owned", "tags": tags, "virtualNetwork": {"id": HUB}}],
                          None, [{"name": "owned-peer", "remoteVirtualNetwork": {"id": HUB}}],
                          None, None, False]
        vpn.cleanup("sub", PRIMARY, outputs, "vpn")
        deletions = [call.args[:5] for call in az.call_args_list if "delete" in call.args]
        self.assertEqual(deletions, [
            ("network", "private-dns", "link", "vnet", "delete"),
            ("network", "vnet", "peering", "delete", "--resource-group"),
            ("group", "delete", "--name", "vpn", "--yes"),
        ])

    @patch.object(vpn, "check_group", return_value=True)
    @patch.object(vpn, "az_json", return_value=[{"name": "unrelated", "tags": {}}])
    def test_cleanup_refuses_unrelated_resources_and_requires_exact_confirmation(self, az, _group):
        outputs = {"vpnResourceGroupId": {"value": "/subscriptions/sub/resourceGroups/vpn"}}
        with self.assertRaisesRegex(ValueError, "confirmation"):
            vpn.cleanup("sub", PRIMARY, outputs, "wrong")
        with self.assertRaisesRegex(ValueError, "unowned resources"):
            vpn.cleanup("sub", PRIMARY, outputs, "vpn")
        self.assertFalse(any("delete" in call.args for call in az.call_args_list))


class VpnNotebookTests(unittest.TestCase):
    def setUp(self):
        notebook = json.loads(NOTEBOOK.read_text(encoding="utf-8"))
        self.cells = {cell["id"]: "".join(cell["source"]) for cell in notebook["cells"]
                      if cell["cell_type"] == "code"}
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.azd = self.stack.enter_context(patch.object(vpn, "_run_json", return_value={
            "AZURE_SUBSCRIPTION_ID": "sub", "AZURE_RESOURCE_GROUP": "primary",
            "AZURE_LOCATION": "region", "APIM_NAME": "apim",
        }))
        self.local_routes = self.stack.enter_context(patch.object(
            vpn, "discover_local_networks", return_value=["192.168.1.0/24"]))
        self.stack.enter_context(patch.object(vpn, "validate_windows_dns_policy"))
        self.stack.enter_context(patch.object(vpn.subprocess, "run",
                                             side_effect=AssertionError("Offline notebook tests cannot start processes.")))
        self.namespace = {}
        self.execute("initialize")
        # Local notebook execution switches are user-editable; offline fixtures must keep them disabled.
        self.namespace.update(deploy_enabled=False, download_client_profiles=False, run_local_validation=False)

    def execute(self, cell):
        exec(compile(self.cells[cell], f"{NOTEBOOK.name}:{cell}", "exec"), self.namespace)

    def prepare_preview_directory(self, directory):
        self.namespace["repo_root"] = Path(directory)
        artifact = Path(directory) / "validation-local" / ".runs" / "developer-vpn" / self.namespace["vpn_resource_group"]
        artifact.mkdir(parents=True)
        for name in ("main.json", "parameters.json"):
            (artifact / name).write_text("{}", encoding="utf-8")

    def write_compiled_parameters(self, path):
        path.write_text(json.dumps({"parameters": {
            name: {"value": value} for name, value in self.namespace["parameters"].items()
        }}), encoding="utf-8")

    def preview_response(self, *arguments, **_kwargs):
        if arguments[:2] == ("bicep", "build-params"):
            self.write_compiled_parameters(Path(arguments[arguments.index("--outfile") + 1]))
        if arguments[:3] == ("deployment", "sub", "what-if"):
            return {"status": "Succeeded", "changes": []}
        return None

    def test_notebook_is_clean_and_every_cell_compiles(self):
        notebook = json.loads(NOTEBOOK.read_text(encoding="utf-8"))
        self.assertEqual(len({cell["id"] for cell in notebook["cells"]}), len(notebook["cells"]))
        for name, source in self.cells.items():
            compile(source, name, "exec")
        for cell in notebook["cells"]:
            if cell["cell_type"] == "code":
                self.assertIsNone(cell["execution_count"])
                self.assertEqual(cell["outputs"], [])
        self.assertFalse(self.namespace["deploy_enabled"])
        self.assertFalse(self.namespace["run_local_validation"])
        self.assertIn("Linux is unsupported", "".join(notebook["cells"][0]["source"]))
        self.assertEqual(self.namespace["vpn_resource_group"], "primary-vpn")
        self.assertEqual(self.namespace["expected_subscription_id"], "sub")
        self.assertIsNone(self.namespace["local_network_cidrs"])
        self.assertIsNone(self.namespace["validation_targets"])
        self.azd.assert_called_once()

    @patch.object(vpn, "az_json")
    def test_subscription_mismatch_never_switches_subscription(self, az):
        az.return_value = {"id": "different", "tenantId": "tenant"}
        with self.assertRaisesRegex(ValueError, "differs"):
            self.execute("account")
        self.assertEqual(az.call_count, 1)

    @patch.object(vpn, "az_json")
    @patch.object(vpn, "inspect_primary", return_value=(vnet(), ["10.170.0.0/24"]))
    @patch.object(vpn, "discover_zones", return_value=[ZONE])
    @patch.object(vpn, "check_group", return_value=False)
    def test_preview_run_leaves_provisioning_profiles_and_local_validation_pending(self, _group, _zones, _primary, az):
        az.side_effect = [{"id": "sub", "name": "fixture", "tenantId": "tenant"},
                          {"name": "AzureCloud"}, {"registrationState": "Registered"}]
        self.execute("account")
        self.execute("discovery")
        self.execute("dns")
        self.local_routes.assert_called_once()
        with tempfile.TemporaryDirectory() as directory:
            # Keep all generated artifacts outside the actual repository.
            self.prepare_preview_directory(directory)
            az.side_effect = self.preview_response
            self.execute("preview")
            self.assertEqual(self.namespace["parameters"]["vpnResourceGroupName"], "primary-vpn")
            self.assertEqual(self.namespace["parameters"]["primaryVnetId"], PRIMARY)
            self.assertEqual(self.namespace["parameters"]["location"], "region")
            az.reset_mock(side_effect=True)
            self.execute("deploy")
            self.execute("azure-verification")
            self.execute("profiles")
            self.execute("local-validation")
            self.execute("summary")
            self.execute("cleanup")
            az.assert_not_called()
        self.assertIsNone(self.namespace["outputs"])
        self.assertFalse(self.namespace["azure_verified"])
        self.assertEqual(self.namespace["local_results"], [])

    @patch.object(vpn, "az_json")
    def test_failed_what_if_cannot_authorize_deployment(self, az):
        self.namespace.update(subscription_id="sub", tenant_id="tenant", zone_ids=[], primary_vnet_id=PRIMARY)
        with tempfile.TemporaryDirectory() as directory:
            self.namespace["repo_root"] = Path(directory)
            az.side_effect = [None, None, {}, {"status": "Failed", "error": {"message": "Denied"}}]
            with self.assertRaisesRegex(RuntimeError, "what-if did not succeed"):
                self.execute("preview")
        self.assertIsNone(self.namespace["previewed_parameters"])

    @patch.object(vpn.shutil, "which", return_value="az")
    def test_preview_cli_contract_handles_empty_validation_but_requires_what_if_json(self, _which):
        empty_success = SimpleNamespace(returncode=0, stdout="", stderr="")
        what_if_success = SimpleNamespace(returncode=0, stderr="",
                                         stdout=json.dumps({"status": "Succeeded", "changes": []}))
        validation_failure = SimpleNamespace(returncode=1, stdout="", stderr="Validation denied")
        for label, validation, what_if, expected_error in (
            ("empty successful validation", empty_success, what_if_success, None),
            ("failed validation", validation_failure, what_if_success, "Azure CLI failed"),
            ("empty what-if", empty_success, empty_success, "Expected Azure CLI JSON"),
        ):
            with self.subTest(case=label), tempfile.TemporaryDirectory() as directory:
                self.namespace.update(subscription_id="sub", tenant_id="tenant", zone_ids=[],
                                      primary_vnet_id=PRIMARY)
                self.prepare_preview_directory(directory)
                responses = [empty_success, empty_success, validation, what_if]
                with patch.object(vpn.subprocess, "run", side_effect=responses) as run:
                    if expected_error:
                        with self.assertRaisesRegex(RuntimeError, expected_error):
                            self.execute("preview")
                        self.assertIsNone(self.namespace["previewed_parameters"])
                    else:
                        self.execute("preview")
                        self.assertIsNotNone(self.namespace["previewed_parameters"])
                        saved = self.namespace["artifact_dir"] / "what-if.json"
                        self.assertEqual(json.loads(saved.read_text())["status"], "Succeeded")
                    self.assertEqual(run.call_count, 3 if validation.returncode else 4)

    @patch.object(vpn, "check_group", return_value=False)
    @patch.object(vpn.shutil, "which", return_value="az")
    def test_preview_avoids_bicep_stdout_noise_and_deploys_only_unchanged_compiled_inputs(self, _which, _group):
        self.namespace.update(subscription_id="sub", tenant_id="tenant", zone_ids=[], primary_vnet_id=PRIMARY)
        installation_message = "Bicep CLI is already installed. Skipping installation as no specific version was requested.\n"

        def run_cli(command, **_kwargs):
            if command[1] == "bicep":
                output = Path(command[command.index("--outfile") + 1])
                if command[2] == "build-params":
                    self.write_compiled_parameters(output)
                else:
                    output.write_text("{}", encoding="utf-8")
                return SimpleNamespace(returncode=0, stdout=installation_message, stderr="")
            template = command[command.index("--template-file") + 1]
            parameters = command[command.index("--parameters") + 1]
            needs_bicep = template.endswith(".bicep") or parameters.endswith(".bicepparam")
            payload = ({"properties": {"provisioningState": "Succeeded", "outputs": {}}}
                       if command[3] == "create" else {"status": "Succeeded", "changes": []})
            return SimpleNamespace(returncode=0, stderr="",
                                   stdout=(installation_message if needs_bicep else "") + json.dumps(payload))

        with tempfile.TemporaryDirectory() as directory:
            self.prepare_preview_directory(directory)
            with patch.object(vpn.subprocess, "run", side_effect=run_cli) as run:
                self.execute("preview")
                arguments = self.namespace["deployment_args"]
                self.assertEqual(Path(arguments[arguments.index("--template-file") + 1]).name, "main.json")
                parameter_argument = arguments[arguments.index("--parameters") + 1]
                self.assertTrue(parameter_argument.startswith("@"))
                self.assertEqual(Path(parameter_argument[1:]).name, "parameters.json")
                self.namespace["deploy_enabled"] = True
                self.execute("deploy")
                self.assertEqual(run.call_args.args[0][1:4], ["deployment", "sub", "create"])
                calls_before_tampering = run.call_count
                for path in self.namespace["previewed_artifacts"]:
                    original = path.read_bytes()
                    path.write_bytes(original + b" ")
                    with self.subTest(path=path.name), self.assertRaisesRegex(ValueError, "changed after preview"):
                        self.execute("deploy")
                    path.write_bytes(original)
                self.assertEqual(run.call_count, calls_before_tampering)

    @patch.object(vpn, "az_json")
    def test_failed_deployment_can_retry_reviewed_plan_after_reinitialization(self, az):
        self.namespace.update(subscription_id="sub", tenant_id="tenant", zone_ids=[], primary_vnet_id=PRIMARY)
        tags = {"managed-by": vpn.OWNER, "primary-vnet-id": PRIMARY}
        with tempfile.TemporaryDirectory() as directory:
            self.prepare_preview_directory(directory)
            az.side_effect = self.preview_response
            self.execute("preview")
            self.namespace["deploy_enabled"] = True
            az.side_effect = [True, {"tags": tags}, RuntimeError("FeatureNotRegistered")]
            with self.assertRaisesRegex(RuntimeError, "FeatureNotRegistered"):
                self.execute("deploy")
            self.assertIsNone(self.namespace["outputs"])
            self.execute("initialize")
            self.assertIsNone(self.namespace["primary_vnet_id"])
            self.namespace["deploy_enabled"] = True
            az.side_effect = [True, {"tags": tags}, {"properties": {
                "provisioningState": "Succeeded", "outputs": {"fixture": {"value": "success"}},
            }}]
            self.execute("deploy")
            self.assertEqual(self.namespace["primary_vnet_id"], PRIMARY)
            self.assertEqual(self.namespace["outputs"]["fixture"]["value"], "success")

    @patch.object(vpn, "az_json")
    def test_retry_does_not_replace_an_explicitly_changed_primary_or_resource_group(self, az):
        self.namespace.update(subscription_id="sub", tenant_id="tenant", zone_ids=[], primary_vnet_id=PRIMARY)
        with tempfile.TemporaryDirectory() as directory:
            self.prepare_preview_directory(directory)
            az.side_effect = self.preview_response
            self.execute("preview")
            az.reset_mock(side_effect=True)
            self.namespace["primary_vnet_id"] = PRIMARY + "-different"
            with self.assertRaisesRegex(ValueError, "changed after preview"):
                self.execute("deploy")
            self.namespace.update(primary_vnet_id=PRIMARY, vpn_resource_group="different-group")
            with self.assertRaisesRegex(ValueError, "changed after preview"):
                self.execute("deploy")
            self.namespace.update(vpn_resource_group="primary-vpn", expected_subscription_id="different-subscription")
            with self.assertRaisesRegex(ValueError, "changed after preview"):
                self.execute("deploy")
            az.assert_not_called()

    @patch.object(vpn, "validate_resolver")
    def test_local_checks_reject_nonprimary_expected_ips_before_dns_or_tls(self, resolver):
        self.namespace.update(azure_verified=True, run_local_validation=True, primary_vnet=vnet(),
                              validation_targets=[{"host": "service.example", "expected_ips": ["192.168.1.2"]}])
        with self.assertRaisesRegex(ValueError, "actual primary VNet"):
            self.execute("local-validation")
        resolver.assert_not_called()

    @patch.object(vpn, "validate_targets", return_value=[{"host": "service.example", "ip": "10.170.0.70", "tls": "TLSv1.3"}])
    @patch.object(vpn, "validate_resolver")
    @patch.object(vpn, "discover_targets", return_value=[{"host": "service.example", "expected_ips": ["10.170.0.70"]}])
    def test_local_checks_use_discovered_targets_without_editing_target_configuration(self, discover, resolver, tls):
        self.namespace.update(azure_verified=True, run_local_validation=True, primary_vnet=vnet(),
                              subscription_id="sub", dns_server_ip="10.171.0.36",
                              outputs={"dnsResolverInboundIp": {"value": "10.171.0.37"}})
        with tempfile.TemporaryDirectory() as directory:
            self.namespace["artifact_dir"] = Path(directory)
            self.execute("local-validation")
            self.assertTrue((Path(directory) / "local-results.json").is_file())
        discover.assert_called_once_with("sub", "primary", vnet(), "apim")
        resolver.assert_called_once()
        self.assertEqual(resolver.call_args.args[0], "10.171.0.37")
        tls.assert_called_once_with(discover.return_value)
        self.assertIsNone(self.namespace["validation_targets"])

    @patch.object(vpn, "download_profiles", return_value=[])
    def test_profile_generation_cannot_replace_the_actual_dns_ip_with_a_stale_plan(self, download):
        self.namespace.update(azure_verified=True, download_client_profiles=True, primary_vnet=vnet(),
                              subscription_id="sub", dns_server_ip="10.171.0.36",
                              outputs={"dnsResolverInboundIp": {"value": "10.171.0.37"}})
        with tempfile.TemporaryDirectory() as directory:
            self.namespace["artifact_dir"] = Path(directory)
            self.execute("profiles")
        self.assertEqual(download.call_args.args[1]["dnsResolverInboundIp"]["value"], "10.171.0.37")
        self.assertEqual(self.namespace["dns_server_ip"], "10.171.0.37")

    @patch.object(vpn, "verify_azure_deployment", side_effect=RuntimeError("not connected"))
    def test_failed_or_disabled_verification_cannot_reuse_old_success(self, _verify):
        self.namespace.update(outputs={"fixture": True}, azure_verified=True, subscription_id="sub")
        with self.assertRaisesRegex(RuntimeError, "not connected"):
            self.execute("azure-verification")
        self.assertFalse(self.namespace["azure_verified"])
        self.namespace.update(local_results=[{"old": "success"}], run_local_validation=False)
        self.execute("local-validation")
        self.assertEqual(self.namespace["local_results"], [])


if __name__ == "__main__":
    unittest.main()
