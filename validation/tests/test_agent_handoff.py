"""Automatic contract handoff discovery and real producer/consumer notebook cells."""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))
from consumerhelpers import find_access_contract_manifest, load_contract_manifest
from test_external_defaults import (
    apim_fixture, cells, execute, snapshot,
)
import validationtools


COORDINATES = {"subscriptionId": "fixture-sub", "resourceGroupName": "fixture-rg", "name": "fixture-apim"}
AGENTS = ("Sales-Assistant", "HR-ChatAgent", "Support-Bot")


def manifest_document(coordinates=None, environment="fixture-env"):
    records = []
    for unit, use_case in (("Sales", "Assistant"), ("HR", "ChatAgent"), ("Support", "Bot")):
        records.append({
            "business_unit": unit, "use_case_name": use_case, "environment": "DEV",
            "product_id": f"LLM-{unit}-{use_case}-DEV",
            "subscription_name": f"LLM-{unit}-{use_case}-DEV-SUB-01",
            "allowed_models": ["gpt-active"],
            "capacity": {"tokens_per_minute": 3000, "token_quota": 100000, "token_quota_period": "Monthly"},
            "use_keyvault": unit == "Sales", "keyvault_name": "external-vault",
            "endpoint_secret": "actual-endpoint", "apikey_secret": "actual-key",
            "use_foundry": unit == "HR", "connection_name": "actual-hr-connection",
            "project_endpoint": "https://agents.services.ai.azure.com/api/projects/agents-project",
            "apim": coordinates or dict(COORDINATES),
        })
    return {"environment": environment, "contracts": records}


def write_manifest(root, name, document, modified):
    path = Path(root) / "validation" / ".runs" / "access-contracts" / name / "access-contracts.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document), encoding="utf-8")
    os.utime(path, ns=(modified, modified))
    return path


class HandoffDiscoveryTests(unittest.TestCase):
    def test_projected_null_connection_objects_do_not_make_sales_or_support_foundry_contracts(self):
        document = manifest_document()
        empty_connection = dict.fromkeys((
            "code", "connectionName", "targetUrl", "foundryAccount", "foundryProject",
            "authType", "managedIdentityAudience",
        ))
        for record in document["contracts"]:
            if record["use_foundry"]:
                record["connections"] = [{
                    "connectionName": "actual-hr-connection",
                    "foundryAccount": "agents", "foundryProject": "agents-project",
                }]
            else:
                record.pop("connection_name")
                record.pop("project_endpoint")
                record["connections"] = [dict(empty_connection)]
        with tempfile.TemporaryDirectory() as root:
            path = write_manifest(root, "projected", document, 1_000_000_000)
            records = load_contract_manifest(path)
            self.assertEqual(find_access_contract_manifest(root, COORDINATES, "fixture-env"), path)
        self.assertNotIn("connection_name", records["Sales-Assistant"])
        self.assertNotIn("project_endpoint", records["Sales-Assistant"])
        self.assertNotIn("connection_name", records["Support-Bot"])
        self.assertEqual(records["HR-ChatAgent"]["connection_name"], "actual-hr-connection")

    def test_foundry_enabled_missing_project_metadata_still_fails(self):
        document = manifest_document()
        hr = document["contracts"][1]
        hr.pop("project_endpoint")
        hr["connections"] = [{"connectionName": "actual-hr-connection",
                              "foundryAccount": None, "foundryProject": None}]
        with tempfile.TemporaryDirectory() as root:
            path = write_manifest(root, "broken-foundry", document, 1_000_000_000)
            with self.assertRaisesRegex(ValueError, "HR-ChatAgent.*Foundry"):
                load_contract_manifest(path)

    def test_newest_complete_manifest_matching_gateway_and_environment_is_selected(self):
        with tempfile.TemporaryDirectory() as root:
            write_manifest(root, "older", manifest_document(), 1_000_000_000)
            latest = write_manifest(root, "latest", manifest_document(), 2_000_000_000)
            write_manifest(root, "other-gateway", manifest_document({**COORDINATES, "name": "other"}), 3_000_000_000)
            write_manifest(root, "other-env", manifest_document(environment="other"), 4_000_000_000)
            partial = manifest_document()
            partial["contracts"] = partial["contracts"][:1]
            write_manifest(root, "partial", partial, 5_000_000_000)
            selected = find_access_contract_manifest(root, COORDINATES, "fixture-env")
            self.assertEqual(selected, latest)
            self.assertEqual(set(load_contract_manifest(selected)), set(AGENTS))

    def test_legacy_handoff_with_record_coordinates_is_supported_case_insensitively(self):
        with tempfile.TemporaryDirectory() as root:
            document = manifest_document({key: value.upper() for key, value in COORDINATES.items()})
            document.pop("environment")
            path = write_manifest(root, "legacy", document, 1_000_000_000)
            self.assertEqual(find_access_contract_manifest(root, COORDINATES, "fixture-env"), path)

    def test_no_matching_gateway_does_not_pick_an_arbitrary_handoff(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertIsNone(find_access_contract_manifest(root, COORDINATES))
            document = manifest_document({**COORDINATES, "subscriptionId": "other-subscription"})
            write_manifest(root, "other", document, 1_000_000_000)
            self.assertIsNone(find_access_contract_manifest(root, COORDINATES))

    def test_equally_recent_matching_handoffs_require_an_explicit_choice(self):
        with tempfile.TemporaryDirectory() as root:
            write_manifest(root, "a", manifest_document(), 1_000_000_000)
            write_manifest(root, "b", manifest_document(), 1_000_000_000)
            with self.assertRaisesRegex(ValueError, "manifest_path"):
                find_access_contract_manifest(root, COORDINATES)

    def test_invalid_or_credential_bearing_matching_manifest_does_not_silently_fall_back(self):
        with tempfile.TemporaryDirectory() as root:
            write_manifest(root, "older", manifest_document(), 1_000_000_000)
            unsafe = manifest_document()
            unsafe["contracts"][0]["api_key"] = "unsafe"
            write_manifest(root, "newer", unsafe, 2_000_000_000)
            with self.assertRaisesRegex(ValueError, "credentials"):
                find_access_contract_manifest(root, COORDINATES)


class ActualNotebookHandoffTests(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.root = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.values = snapshot()
        self.values.pop("VALIDATION_AGENT_CONTRACTS", None)
        self.account = {"id": "fixture-sub", "tenantId": "fixture-tenant"}

    def initialize(self, settings=None, values=None):
        namespace = {}
        execute(cells("agent-frameworks")[0], namespace)
        namespace["root"] = self.root
        namespace["run_dir"] = self.root / "agent-run"
        if settings:
            namespace.update(settings)
        apim = apim_fixture()
        namespace["APIMClientTool"] = Mock(return_value=apim)
        with patch.object(validationtools, "_run_json", side_effect=[values or self.values, self.account]):
            execute(cells("agent-frameworks")[1], namespace)
        return namespace, apim

    def test_default_initialization_discovers_all_three_without_path_or_records(self):
        path = write_manifest(self.root, "previous-run", manifest_document(), 1_000_000_000)
        namespace, apim = self.initialize()
        self.assertEqual(namespace["manifest_path"], path)
        self.assertEqual(set(namespace["resolved"]), set(AGENTS))
        self.assertEqual([call.args[0] for call in apim.get_subscription_key.call_args_list], [
            "LLM-Sales-Assistant-DEV-SUB-01", "LLM-HR-ChatAgent-DEV-SUB-01", "LLM-Support-Bot-DEV-SUB-01",
        ])
        self.assertEqual(namespace["resolved"]["Sales-Assistant"]["config"]["keyvault_name"], "external-vault")
        self.assertEqual(namespace["resolved"]["HR-ChatAgent"]["config"]["connection_name"], "actual-hr-connection")
        self.assertTrue(all(item["model"] == "gpt-active" for item in namespace["resolved"].values()))

    def test_missing_predecessor_has_actionable_automatic_discovery_instructions(self):
        with self.assertRaisesRegex(ValueError, "Run Access Contracts first"):
            self.initialize()

    def test_explicit_path_and_records_override_automatic_selection(self):
        write_manifest(self.root, "newest", manifest_document(), 3_000_000_000)
        old = manifest_document()
        for item in old["contracts"]:
            item["product_id"] = "pinned-" + item["product_id"]
            item["subscription_name"] = "pinned-" + item["subscription_name"]
        path = write_manifest(self.root, "explicit", old, 1_000_000_000)
        namespace, _ = self.initialize({"manifest_path": path})
        self.assertEqual(namespace["manifest_path"], path)
        self.assertTrue(all(item["config"]["product_id"].startswith("pinned-")
                            for item in namespace["resolved"].values()))
        records = load_contract_manifest(path)
        namespace, _ = self.initialize({"contract_records": records}, values={
            **self.values, "VALIDATION_ACCESS_CONTRACTS_MANIFEST": str(self.root / "does-not-exist.json"),
        })
        self.assertIsNone(namespace["manifest_path"])
        self.assertTrue(all(item["config"]["product_id"].startswith("pinned-")
                            for item in namespace["resolved"].values()))

    def test_actual_access_contract_producer_manifest_is_automatically_consumed(self):
        namespace = {}
        execute(cells("access-contracts")[0], namespace)
        namespace.update(root=self.root, run_dir=self.root / "validation" / ".runs" / "access-contracts" / "producer",
                         run_id="producer")
        namespace["keyvault"] = json.loads(self.values["VALIDATION_EXTERNAL_KEYVAULT"])
        namespace["foundry"] = json.loads(self.values["VALIDATION_EXTERNAL_FOUNDRY"])
        namespace["APIMClientTool"] = Mock(return_value=apim_fixture())
        with patch.object(validationtools, "_run_json", side_effect=[self.values, self.account]):
            execute(cells("access-contracts")[1], namespace)
        namespace["run_dir"] = self.root / "validation" / ".runs" / "access-contracts" / "producer"
        namespace["run_dir"].mkdir(parents=True, exist_ok=True)
        execute(cells("access-contracts")[2], namespace)
        namespace["generated"] = [(contract, Path("fixture.bicepparam")) for contract in namespace["access_contracts"]]
        outputs = []
        for contract in namespace["access_contracts"]:
            outputs.append({
                "endpoints": {"value": [{"productId": contract["product_id"]}]},
                "subscriptions": {"value": [{"productId": contract["product_id"],
                                            "name": contract["product_id"] + "-SUB-01"}]},
                "foundryConnections": {"value": [{
                    "connectionName": "actual-hr-connection",
                }] if contract["use_foundry"] else [{
                    "code": None, "connectionName": None, "targetUrl": None,
                    "foundryAccount": None, "foundryProject": None,
                    "authType": None, "managedIdentityAudience": None,
                }]},
            })
        namespace["deploy_contract"] = Mock(side_effect=outputs)
        execute(cells("access-contracts")[4], namespace)
        loaded, _ = self.initialize()
        self.assertEqual(loaded["manifest_path"], namespace["manifest_path"])
        self.assertEqual(loaded["resolved"]["HR-ChatAgent"]["config"]["connection_name"],
                         "actual-hr-connection")
        self.assertEqual(loaded["resolved"]["Sales-Assistant"]["config"]["keyvault_name"], "external-vault")

    def test_auto_discovery_does_not_bypass_model_skip_keywords(self):
        write_manifest(self.root, "previous-run", manifest_document(), 1_000_000_000)
        with self.assertRaises(validationtools.ValidationBlocked):
            self.initialize({"skipped_models": ["ACTIVE"]})

    def test_title_overview_maps_three_frameworks_to_their_contracts(self):
        notebook = json.loads((ROOT / "validation" / "citadel-agent-frameworks-tests.ipynb").read_text(encoding="utf-8"))
        overview = "".join(notebook["cells"][0]["source"])
        for label in ("Microsoft Agent Framework", "Foundry", "LangChain",
                      "Sales", "HR", "Support", "automatically"):
            self.assertIn(label, overview)


if __name__ == "__main__":
    unittest.main()
