"""Execute the six external-scenario notebooks against offline azd/APIM fixtures."""
import ast
import base64
import contextlib
import io
import json
import os
import sys
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, create_autospec, patch
from azure.mgmt.apimanagement.operations import ProductPolicyOperations

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))
import apimtools
import utils
import validationtools
import consumerhelpers

NAMES = ("access-contracts", "agent-frameworks", "alerting",
         "jwt-authentication", "pii-processing", "publish-contract")


def cells(name):
    notebook = json.loads(
        (ROOT / "validation" / f"citadel-{name}-tests.ipynb").read_text(encoding="utf-8")
    )
    return ["".join(cell["source"]) for cell in notebook["cells"] if cell["cell_type"] == "code"]


def execute(source, namespace):
    exec(compile(source, "<actual-notebook-cell>", "exec"), namespace)


def records():
    return {
        name: {
            "product_id": f"exact-{name}", "subscription_name": f"exact-{name}-SUB-01",
            "allowed_models": ["gpt-MINI-blue", "gpt-active"],
            "capacity": {"tokens_per_minute": 3000, "token_quota": 100000,
                         "token_quota_period": "Monthly"},
            "use_keyvault": name == "Sales-Assistant", "keyvault_name": "external-vault",
            "endpoint_secret": "existing-endpoint", "apikey_secret": "existing-key",
            "use_foundry": name == "HR-ChatAgent", "connection_name": "actual-connection",
            "project_endpoint": "https://existing.services.ai.azure.com/api/projects/existing-project",
        } for name in ("Sales-Assistant", "HR-ChatAgent", "Support-Bot")
    }


def snapshot():
    return {
        "AZURE_SUBSCRIPTION_ID": "fixture-sub", "AZURE_TENANT_ID": "fixture-tenant",
        "AZURE_RESOURCE_GROUP": "fixture-rg", "AZURE_LOCATION": "fixture-location",
        "AZURE_ENV_NAME": "fixture-env", "APIM_NAME": "fixture-apim",
        "LLM_BACKEND_CONFIG": json.dumps([{
            "backendId": "fixture-backend", "backendType": "ai-foundry",
            "endpoint": "https://existing.services.ai.azure.com",
            "supportedModels": [{"name": name} for name in
                                ("gpt-MINI-blue", "gpt-active", "text-embedding", "flux-image")],
        }]),
        "VALIDATION_SKIPPED_MODELS": '["mInI"]',
        "ENTRA_TENANT_ID": "fixture-tenant", "ENTRA_CLIENT_ID": "fixture-client",
        "ENTRA_AUDIENCE": "api://fixture-client",
        "COSMOS_DB_ACCOUNT_NAME": "actual-cosmos",
        "APIM_APP_INSIGHTS_NAME": "actual-gateway-telemetry",
        "VALIDATION_ALERT_EMAIL": "operator@example.com",
        "FOUNDRY_ACCOUNT_NAME": "existing-foundry",
        "FOUNDRY_PROJECT_NAME": "existing-project",
        "FOUNDRY_PROJECT_ENDPOINT":
            "https://existing-foundry.services.ai.azure.com/api/projects/existing-project",
        "VALIDATION_FOUNDRY_AGENT_NAME": "existing-hr-agent",
        "VALIDATION_EXTERNAL_KEYVAULT": json.dumps({
            "subscriptionId": "external-sub", "resourceGroupName": "external-rg",
            "name": "external-vault",
        }),
        "VALIDATION_EXTERNAL_FOUNDRY": json.dumps({
            "subscriptionId": "external-sub", "resourceGroupName": "external-rg",
            "accountName": "external-foundry", "projectName": "external-project",
        }),
        "VALIDATION_AGENT_CONTRACTS": json.dumps(records()),
    }


def secret_environment():
    claims = base64.urlsafe_b64encode(
        json.dumps({"exp": time.time() + 600, "aud": "api://fixture-client"}).encode()
    ).decode().rstrip("=")
    return {
        "VALIDATION_ENTRA_CLIENT_SECRET": "offline-secret-fixture",
        "VALIDATION_JWT_NO_ROLE_TOKEN": f"fixture.{claims}.offline-signature",
    }


def apim_fixture():
    apim = Mock()
    apim.client.product.list_by_service.return_value = []
    apim.client.product_policy = create_autospec(ProductPolicyOperations, instance=True)
    apim.apim_resource_name = "fixture-apim"
    apim.apim_service_id = (
        "/subscriptions/fixture-sub/resourceGroups/fixture-rg/providers/"
        "Microsoft.ApiManagement/service/fixture-apim"
    )
    apim.apim_resource_gateway_url = "https://fixture-apim.azure-api.net"
    apim.client.product_api.list_by_product.return_value = [
        SimpleNamespace(name="universal-llm-api")
    ]
    apim.client.product_policy.get.return_value = SimpleNamespace(value=(
        '<policies><inbound><set-variable name="allowedModels" '
        'value="gpt-MINI-blue,gpt-active"/>'
        '<llm-token-limit tokens-per-minute="3000" token-quota="100000" '
        'token-quota-period="Monthly"/></inbound></policies>'
    ))
    apim.discover_api_exact.return_value = {"url": "https://fixture-apim.azure-api.net/models"}
    apim.get_subscription_key.return_value = "offline-subscription-key-fixture"
    return apim


class ExternalDefaultsTests(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.stack.enter_context(patch.object(Path, "mkdir"))
        self.stack.enter_context(patch.object(
            utils, "run", side_effect=AssertionError("Unexpected Azure CLI call")))
        self.stack.enter_context(patch("subprocess.run", side_effect=AssertionError("Unexpected process")))
        self.stack.enter_context(patch.dict(os.environ, secret_environment()))

    def configured(self, name):
        namespace = {}
        execute(cells(name)[0], namespace)
        if name == "access-contracts":
            # Isolate configuration resolution from local notebook target customizations.
            namespace["keyvault"] = {field: "REPLACE" for field in namespace["keyvault"]}
            namespace["foundry"] = {field: "REPLACE" for field in namespace["foundry"]}
        return namespace

    def initialize(self, name, values=None, namespace=None, expected=None):
        namespace = namespace if namespace is not None else self.configured(name)
        values = values if values is not None else snapshot()
        account = {"id": "fixture-sub", "tenantId": "fixture-tenant"}
        apim = apim_fixture()
        namespace["APIMClientTool"] = Mock(return_value=apim)
        with patch.object(validationtools, "_run_json", side_effect=[values, account]) as commands, \
                patch.object(apimtools, "APIMClientTool", return_value=apim):
            if expected:
                with self.assertRaisesRegex((ValueError, validationtools.ValidationError), expected):
                    execute(cells(name)[1], namespace)
            else:
                execute(cells(name)[1], namespace)
            self.assertEqual(commands.call_count, 2)
        return namespace, apim

    def test_supplied_azd_values_initialize_all_six_without_editing_configuration(self):
        for name in NAMES:
            with self.subTest(notebook=name):
                namespace, apim = self.initialize(name)
                self.assertFalse(namespace.get("cleanup_enabled", False))
                self.assertFalse(namespace.get("cleanup_delete_contract", False))
                context = namespace["context"]
                self.assertEqual(context.catalog.models_for("chat"), ["gpt-active"])
                self.assertEqual(context.catalog.models_for("responses"), ["gpt-active"])
                if name == "access-contracts":
                    self.assertEqual(namespace["keyvault"]["name"], "external-vault")
                    self.assertEqual(namespace["foundry"]["accountName"], "external-foundry")
                    execute(cells(name)[2], namespace)
                    self.assertTrue(all(item["allowed_models"] == ["gpt-active"]
                                        for item in namespace["access_contracts"]))
                elif name == "agent-frameworks":
                    self.assertEqual({item["model"] for item in namespace["resolved"].values()},
                                     {"gpt-active"})
                    self.assertEqual(apim.get_subscription_key.call_count, 3)
                    self.assertEqual(
                        [call.args[0] for call in apim.get_subscription_key.call_args_list],
                        [f"exact-{agent}-SUB-01" for agent in records()],
                    )
                elif name == "pii-processing":
                    self.assertEqual(namespace["cosmos_account_endpoint"],
                                     "https://actual-cosmos.documents.azure.com")
                elif name == "publish-contract":
                    self.assertEqual(namespace["foundry_agent_name"], "existing-hr-agent")
                    self.assertEqual(namespace["app_insights_name_override"], "actual-gateway-telemetry")
                elif name == "jwt-authentication":
                    self.assertEqual(namespace["entra_tenant_id"], "fixture-tenant")
                    self.assertEqual(namespace["entra_audience"], "api://fixture-client")
                elif name == "alerting":
                    self.assertEqual(namespace["alert_email_address"], "operator@example.com")
                    self.assertEqual(namespace["app_insights_name"], "actual-gateway-telemetry")

    def test_genuine_external_prerequisites_are_not_fabricated(self):
        cases = (
            ("access-contracts", ("VALIDATION_EXTERNAL_KEYVAULT", "VALIDATION_EXTERNAL_FOUNDRY"),
             "keyvault.name"),
            ("agent-frameworks", ("VALIDATION_AGENT_CONTRACTS",), "predecessor"),
            ("publish-contract", ("VALIDATION_FOUNDRY_AGENT_NAME",), "existing agent"),
            ("pii-processing", ("COSMOS_DB_ACCOUNT_NAME",), "pii_state_evidence"),
        )
        for name, removed, message in cases:
            with self.subTest(notebook=name):
                values = snapshot()
                for key in removed:
                    values.pop(key)
                # Hub resources are not evidence of the user's chosen external target.
                values["KEY_VAULT_NAME"] = "hub-vault"
                values["AI_FOUNDRY_SERVICES"] = json.dumps([{
                    "name": "hub-foundry", "projects": [{"name": "hub-project"}]
                }])
                self.initialize(name, values=values, expected=message)

    def test_jwt_secret_and_no_role_fixture_remain_required(self):
        for missing, label in (
            ("VALIDATION_ENTRA_CLIENT_SECRET", "entra.client_secret"),
            ("VALIDATION_JWT_NO_ROLE_TOKEN", "jwt.no_role_token_fixture"),
        ):
            with self.subTest(missing=missing), patch.dict(os.environ, {missing: ""}):
                self.initialize("jwt-authentication", expected=label)

    def test_access_contract_does_not_require_a_project_token_with_real_targets(self):
        with patch.dict(os.environ, {"VALIDATION_FOUNDRY_PROJECT_TOKEN": ""}):
            namespace, _ = self.initialize("access-contracts")
        self.assertNotIn("project_mi_token", namespace)

    def test_disabled_external_integrations_do_not_require_their_unused_inputs(self):
        namespace = self.configured("access-contracts")
        namespace["use_keyvault_integration"] = False
        namespace["use_foundry_integration"] = False
        values = snapshot()
        values["VALIDATION_EXTERNAL_KEYVAULT"] = "unused malformed target"
        values["VALIDATION_EXTERNAL_FOUNDRY"] = "unused malformed target"
        self.initialize("access-contracts", values=values, namespace=namespace)

    def test_genuinely_supplied_azd_secret_fixtures_do_not_require_notebook_edits(self):
        fixtures = secret_environment()
        values = {**snapshot(), **fixtures}
        with patch.dict(os.environ, {name: "" for name in fixtures}):
            access, _ = self.initialize("access-contracts", values=values)
            jwt, _ = self.initialize("jwt-authentication", values=values)
        self.assertNotIn("project_mi_token", access)
        self.assertEqual(jwt["entra_client_secret"], fixtures["VALIDATION_ENTRA_CLIENT_SECRET"])
        self.assertEqual(jwt["no_role_token_fixture"], fixtures["VALIDATION_JWT_NO_ROLE_TOKEN"])

    def test_unknown_external_grants_and_connections_remain_actionable(self):
        for missing in ("allowed_models", "connection_name"):
            with self.subTest(missing=missing):
                values = snapshot()
                contracts = records()
                contracts["HR-ChatAgent"].pop(missing)
                values["VALIDATION_AGENT_CONTRACTS"] = json.dumps(contracts)
                self.initialize("agent-frameworks", values=values, expected=missing)

    def test_every_model_selection_respects_skip_and_empty_operation_overrides(self):
        for name in NAMES:
            for override in (False, True):
                with self.subTest(notebook=name, disabled_by_override=override):
                    values = snapshot()
                    if override:
                        values["VALIDATION_MODEL_CAPABILITIES"] = json.dumps({
                            "gpt-MINI-blue": [], "gpt-active": [],
                            "text-embedding": [], "flux-image": [],
                        })
                    else:
                        values["VALIDATION_SKIPPED_MODELS"] = '["GPT", "text", "FLUX"]'
                    self.initialize(name, values=values,
                                    expected="No eligible GPT chat model" if name == "alerting" else "No models selected")

    def test_unrelated_unmapped_image_model_does_not_block_chat_scenarios(self):
        for name in NAMES:
            with self.subTest(notebook=name):
                values = snapshot()
                values["VALIDATION_INFER_OPERATIONS"] = "false"
                values["VALIDATION_MODEL_CAPABILITIES"] = json.dumps({
                    "gpt-active": ["chat", "responses"],
                })
                namespace, _ = self.initialize(name, values=values)
                self.assertEqual(namespace["context"].catalog.operations("flux-image"), [])

    def test_agent_rebuilt_catalog_keeps_global_allowed_model_intersection(self):
        values = snapshot()
        values["VALIDATION_SKIPPED_MODELS"] = "[]"
        namespace = self.configured("agent-frameworks")
        namespace["overrides"]["allowed_models"] = ["gpt-active"]
        namespace, _ = self.initialize("agent-frameworks", values=values, namespace=namespace)
        self.assertEqual({item["model"] for item in namespace["resolved"].values()}, {"gpt-active"})

    def test_skipped_agent_model_override_cannot_escape_predecessor_intersection(self):
        namespace = self.configured("agent-frameworks")
        namespace["model_overrides"]["HR-ChatAgent"] = "gpt-MINI-blue"
        self.initialize("agent-frameworks", namespace=namespace, expected="not available|skipped|supports")

    def test_exact_apim_logger_metadata_resolves_telemetry_without_a_named_component(self):
        resource_id = (
            "/subscriptions/telemetry-sub/resourceGroups/telemetry-rg/"
            "providers/microsoft.insights/components/exact-gateway-component"
        )
        values = snapshot()
        values.pop("APIM_APP_INSIGHTS_NAME")
        for name in ("alerting", "publish-contract"):
            with self.subTest(notebook=name):
                namespace = self.configured(name)
                with patch.object(consumerhelpers, "cli_json", return_value={"value": [resource_id]}):
                    namespace, _ = self.initialize(name, values=values, namespace=namespace)
                if name == "alerting":
                    self.assertEqual(namespace["app_insights_coordinates"], {
                        "subscriptionId": "telemetry-sub", "resourceGroupName": "telemetry-rg",
                        "name": "exact-gateway-component",
                    })
                else:
                    self.assertEqual(namespace["app_insights_name_override"], "exact-gateway-component")
                    self.assertEqual(namespace["app_insights_resource_group"], "telemetry-rg")
                    self.assertEqual(namespace["app_insights_subscription_id"], "telemetry-sub")

    def test_ambiguous_logger_metadata_requires_a_real_component_not_an_arbitrary_first(self):
        values = snapshot()
        values.pop("APIM_APP_INSIGHTS_NAME")
        for name in ("alerting", "publish-contract"):
            with self.subTest(notebook=name):
                namespace = self.configured(name)
                component_ids = [
                    f"/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Insights/components/{n}"
                    for n in ("one", "two")
                ]
                with patch.object(consumerhelpers, "cli_json", return_value={"value": component_ids}):
                    self.initialize(name, values=values, namespace=namespace, expected="APIM_APP_INSIGHTS_NAME")

    def test_access_contract_handoff_carries_real_publication_and_subscription_metadata(self):
        namespace, _ = self.initialize("access-contracts")
        execute(cells("access-contracts")[2], namespace)
        namespace["generated"] = [(record, Path("offline-main.bicepparam"))
                                  for record in namespace["access_contracts"]]
        outputs = []
        for record in namespace["access_contracts"]:
            outputs.append({
                "endpoints": {"value": [{"productId": record["product_id"]}]},
                "subscriptions": {"value": [{
                    "productId": record["product_id"],
                    "subscriptionId": "/subscriptions/exact-parent/subscriptions/actual-" + record["business_unit"],
                }]},
                "foundryConnections": {"value": (
                    [{"connectionName": "actual-output-connection"}] if record["use_foundry"] else []
                )},
            })
        namespace["deploy_contract"] = Mock(side_effect=outputs)
        with patch.object(Path, "write_text"):
            execute(cells("access-contracts")[4], namespace)
        handoff = namespace["manifest"]["contracts"]
        self.assertEqual([record["subscription_name"] for record in handoff],
                         ["actual-Sales", "actual-HR", "actual-Support"])
        self.assertEqual(handoff[0]["keyvault_name"], "external-vault")
        self.assertEqual(handoff[1]["connection_name"], "actual-output-connection")
        self.assertIn("external-foundry", handoff[1]["project_endpoint"])
        self.assertEqual(handoff[0]["capacity"]["tokens_per_minute"], 3000)
        self.assertFalse(any("token" == key or "key" == key for record in handoff for key in record))

    def test_publish_contract_actual_grant_cell_excludes_skipped_models(self):
        namespace, apim = self.initialize("publish-contract")
        namespace.update(
            apimClientTool=apim, apim_name="fixture-apim",
            assets=[{"name": "actual-tool", "assetType": "mcp-existing"}],
            write_parameters=Mock(return_value=Path("offline-main.bicepparam")),
            preview=Mock(return_value="offline preview"),
        )
        apim.client.api.list_by_service.return_value = [SimpleNamespace(name="universal-llm-api")]
        source = next(source for source in cells("publish-contract") if "allowed_models_csv =" in source)
        execute(source, namespace)
        self.assertEqual(namespace["allowed_models_csv"], "gpt-active")
        self.assertIn('name="allowedModels" value="gpt-active"', namespace["policy_xml"])

    def test_existing_agent_project_endpoint_is_used_by_the_actual_enablement_cell(self):
        namespace, _ = self.initialize("publish-contract")
        namespace["foundry_project_endpoint"] = "https://actual-project.example/api/projects/actual"
        source = next(source for source in cells("publish-contract")
                      if 'a2a_card_backend_url = ""' in source)
        with patch.object(utils, "run", return_value=SimpleNamespace(text="offline-token")), \
                patch.object(utils, "http_call", return_value=SimpleNamespace(
                    status_code=200, text="enabled")) as request:
            execute(source, namespace)
        self.assertTrue(request.call_args.args[1].startswith(
            "https://actual-project.example/api/projects/actual/agents/existing-hr-agent"))

    def test_actual_azd_foundry_project_output_is_used_but_never_invents_an_agent(self):
        values = snapshot()
        for key in ("FOUNDRY_ACCOUNT_NAME", "FOUNDRY_PROJECT_NAME", "FOUNDRY_PROJECT_ENDPOINT"):
            values.pop(key)
        values["AI_FOUNDRY_SERVICES"] = json.dumps([{
            "name": "actual-account", "cognitiveServiceName": "actual-account",
            "endpoint": "https://actual-account.cognitiveservices.azure.com/",
            "foundryProjectEndpoint":
                "https://actual-account.services.ai.azure.com/api/projects/actual-project",
        }])
        namespace, _ = self.initialize("publish-contract", values=values)
        self.assertEqual(namespace["foundry_account_name"], "actual-account")
        self.assertEqual(namespace["foundry_project_name"], "actual-project")
        self.assertEqual(namespace["foundry_project_endpoint"],
                         "https://actual-account.services.ai.azure.com/api/projects/actual-project")
        values.pop("VALIDATION_FOUNDRY_AGENT_NAME")
        self.initialize("publish-contract", values=values, expected="existing agent")

    def test_ambiguous_foundry_inventory_requires_a_selected_existing_target(self):
        values = snapshot()
        for key in ("FOUNDRY_ACCOUNT_NAME", "FOUNDRY_PROJECT_NAME", "FOUNDRY_PROJECT_ENDPOINT"):
            values.pop(key)
        values["AI_FOUNDRY_SERVICES"] = json.dumps([{
            "cognitiveServiceName": account,
            "foundryProjectEndpoint":
                f"https://{account}.services.ai.azure.com/api/projects/project",
        } for account in ("one-account", "two-account")])
        self.initialize("publish-contract", values=values, expected="a2a.foundry_account_name")

    def test_missing_telemetry_evidence_is_still_blocked_after_supplied_azd_inputs(self):
        namespace, _ = self.initialize("publish-contract")
        namespace.update(
            asset_metric_names=["actual-tool", "actual-agent"], sub_name="actual-subscription",
            run_started_at="2026-01-01T00:00:00Z", telemetry_poll_attempts=1,
        )
        source = next(source for source in cells("publish-contract")
                      if 'expected_metrics = {"McpRequests"}' in source)
        with patch.object(utils, "run", return_value=SimpleNamespace(
                success=True, json_data={"tables": []})):
            execute(source, namespace)
        self.assertEqual(namespace["run"].results[-1].status, "BLOCKED")
        self.assertIn("No fresh metric evidence", namespace["run"].results[-1].reason)

    def test_all_actual_code_cells_compile_including_async_framework_examples(self):
        for name in NAMES:
            for index, source in enumerate(cells(name)):
                with self.subTest(notebook=name, cell=index):
                    compile(source, f"{name}:{index}", "exec", flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)


if __name__ == "__main__":
    unittest.main()
