"""Offline helper and notebook-cell execution regressions; Azure boundaries are mocked."""

import ast
import base64
import copy
import io
import json
import re
import time
import unittest
import xml.etree.ElementTree as ET
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
from shared import utils as notebook_utils

from shared.contracttools import access_policy
from shared.scenariotools import (
    access_parameters, cleanup_products, completion_text, contract_identity,
    policy_xml, save_manifest,
)
from shared.validationtools import (
    ModelCatalog, ValidationBlocked, ValidationError, ValidationRun,
)

ROOT = Path(__file__).resolve().parents[2]


def notebook_cell(scenario, needle):
    notebook = json.loads(
        (ROOT / "validation" / f"citadel-{scenario}-tests.ipynb").read_text(encoding="utf-8")
    )
    return next(
        "".join(cell["source"]) for cell in notebook["cells"]
        if cell["cell_type"] == "code" and needle in "".join(cell["source"])
    )


def notebook_functions(source, namespace):
    body = ast.parse(source).body
    if len(body) == 1 and isinstance(body[0], ast.With):
        body = body[0].body
    nodes = []
    def collect(statements):
        for node in statements:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                nodes.append(node)
            elif isinstance(node, ast.If):
                collect(node.body)
                collect(node.orelse)
    collect(body)
    exec(compile(ast.Module(nodes, type_ignores=[]), "<notebook-functions>", "exec"), namespace)


def synthetic_context():
    catalog = ModelCatalog(
        [{"backendId": "backend", "backendType": "azure-openai",
          "supportedModels": [{"name": "future-model"}]}],
        {"future-model": ["chat", "responses", "image-generation", "image-edit"]},
    )
    return SimpleNamespace(
        config={"resource_group": "rg", "subscription_id": "subscription",
                "location": "eastus", "apim_name": "gateway", "llm_backends": [],
                "environment": "offline", "api_key": "synthetic-not-for-output"},
        account={"tenantId": "tenant"}, catalog=catalog,
    )


def synthetic_contract():
    return {
        "name": "deployment", "business_unit": "Tests", "use_case_name": "Run",
        "environment": "DEV", "use_keyvault": False, "description": "Feature contract",
        "endpoint_secret": "ENDPOINT", "apikey_secret": "KEY",
    }


def outputs(product_id="actual-product", subscription="actual-subscription"):
    return {
        "products": {"type": "Array", "value": [{"productId": product_id}]},
        "subscriptions": {"type": "Array", "value": [
            {"productId": product_id, "name": subscription},
        ]},
    }


class ScenarioHelperTests(unittest.TestCase):
    def test_access_parameters_preserve_policy_and_default_api_grants(self):
        context, contract = synthetic_context(), synthetic_contract()
        before = copy.deepcopy(contract)
        policy = '<policies><inbound><base /></inbound></policies>'
        parameters = access_parameters(context, SimpleNamespace(apim_resource_name="gateway"), contract, policy)
        self.assertEqual(parameters["apim"], {
            "subscriptionId": "subscription", "resourceGroupName": "rg", "name": "gateway",
        })
        self.assertEqual(parameters["apiNameMapping"]["LLM"], [
            "universal-llm-api", "azure-openai-api", "unified-ai-api",
        ])
        self.assertEqual(parameters["services"][0]["policyXml"], policy)
        self.assertEqual(parameters["productTerms"], "Feature contract")
        self.assertFalse(parameters["useTargetAzureKeyVault"])
        self.assertFalse(parameters["useTargetFoundry"])
        self.assertEqual(contract, before)

    def test_mixed_asset_and_external_vault_fields_are_lossless(self):
        contract = {**synthetic_contract(), "use_keyvault": True}
        vault = {"subscriptionId": "external", "resourceGroupName": "external-rg", "name": "vault"}
        endpoints = [{"apiName": "weather-tool"}, {"apiName": "hr-agent", "endpointSecretName": "HR-ENDPOINT"}]
        parameters = access_parameters(
            synthetic_context(), SimpleNamespace(apim_resource_name="gateway"), contract, "policy",
            code="MULTI", api_names=["weather-tool", "hr-agent"],
            key_vault=vault, service_options={"assetEndpoints": endpoints, "foundryApiName": "models"},
        )
        self.assertEqual(parameters["keyVault"], vault)
        self.assertEqual(parameters["apiNameMapping"], {"MULTI": ["weather-tool", "hr-agent"]})
        self.assertEqual(parameters["services"][0]["assetEndpoints"], endpoints)
        self.assertEqual(parameters["services"][0]["foundryApiName"], "models")
        self.assertTrue(parameters["useTargetAzureKeyVault"])

    def test_enabled_vault_requires_all_named_coordinates(self):
        contract = {**synthetic_contract(), "use_keyvault": True}
        for vault in [None, {}, {"name": "vault"},
                      {"subscriptionId": "sub", "resourceGroupName": "", "name": "vault"},
                      {"subscriptionId": "sub", "resourceGroupName": "rg", "name": "REPLACE"}]:
            with self.subTest(vault=vault), self.assertRaises(ValueError):
                access_parameters(synthetic_context(), SimpleNamespace(apim_resource_name="gateway"),
                                  contract, "policy", key_vault=vault)

    def test_policy_escape_preserves_csharp_regex_and_xml_structure(self):
        source = r'''<policies><inbound>
<when condition="@(context.Variables.GetValueOrDefault<string>("mode") == "mask" &amp;&amp; true)" />
<set-variable name="regex" value="@{ return @"\b\d{4}\b"; }" />
</inbound><outbound><set-body>@(context.Variables.GetValueOrDefault<string>("body"))</set-body></outbound></policies>'''
        # Handwritten expressions are raw C#, including '&', rather than pre-escaped XML.
        source = source.replace("&amp;&amp;", "&&")
        root = ET.fromstring(policy_xml(source))
        self.assertEqual(root.find("./inbound/when").get("condition"),
            '@(context.Variables.GetValueOrDefault<string>("mode") == "mask" && true)')
        self.assertIn(r'@"\b\d{4}\b"', root.find("./inbound/set-variable").get("value"))
        self.assertEqual(root.find("./outbound/set-body").text,
            '@(context.Variables.GetValueOrDefault<string>("body"))')
        with self.assertRaises(ET.ParseError):
            policy_xml("<policies><broken></policies>")

    def test_preserved_pii_policies_keep_feature_semantics(self):
        for name, inbound_fragment in [("pii_masking_policy", "pii-anonymization"),
                                       ("pii_blocking_policy", "pii-anonymization")]:
            namespace = {"policy_xml": policy_xml, "utils": notebook_utils}
            with redirect_stdout(io.StringIO()):
                exec(notebook_cell("pii-processing", name + " ="), namespace)
            root = ET.fromstring(namespace[name])
            self.assertIsNotNone(root.find(f".//inbound//include-fragment[@fragment-id='{inbound_fragment}']"))
            regex = root.find(".//set-variable[@name='piiRegexPatterns']").get("value")
            self.assertIn(r"\b", regex)
            self.assertNotIn("\x08", regex)
            if name == "pii_masking_policy":
                for fragment in ["pii-deanonymization", "pii-state-saving"]:
                    self.assertIsNotNone(root.find(f".//outbound//include-fragment[@fragment-id='{fragment}']"))
                self.assertEqual(root.find(".//set-variable[@name='piiConfidenceThreshold']").get("value"), "0.8")
            else:
                self.assertEqual(root.find(".//return-response/set-status").get("code"), "400")
                self.assertIn("PII_DETECTED", root.find(".//return-response/set-body").text)

    def test_malformed_completion_bodies_cannot_be_positive_evidence(self):
        malformed = [None, [], {}, {"choices": []}, {"choices": [None]},
                     {"choices": [{"message": None}]},
                     {"choices": [{"message": {"content": []}}]}]
        for body in malformed:
            with self.subTest(body=body):
                self.assertEqual(completion_text(body), "")
        self.assertEqual(completion_text({"choices": [{"message": {"content": "answer"}}]}), "answer")

    def test_identity_uses_output_ids_and_excludes_reused_products(self):
        owned = set()
        self.assertEqual(contract_identity(outputs(), set(), owned),
                         ("actual-product", "actual-subscription"))
        self.assertEqual(owned, {"actual-product"})
        reused = set()
        contract_identity(outputs(), {"actual-product"}, reused)
        self.assertFalse(reused)
        invalid = outputs()
        invalid["subscriptions"]["value"][0]["productId"] = "different-product"
        with self.assertRaises(ValueError):
            contract_identity(invalid, set(), set())
        with self.assertRaises(ValueError):
            contract_identity({}, set(), set())

    def test_cleanup_off_and_only_owned_products_are_deleted(self):
        apim = SimpleNamespace(resource_group_name="rg", apim_resource_name="gateway", client=Mock())
        owned = {"run-owned-product"}
        with redirect_stdout(io.StringIO()):
            cleanup_products(apim, owned)
            apim.client.product.delete.assert_not_called()
            cleanup_products(apim, owned, enabled=True)
        apim.client.product.delete.assert_called_once_with(
            resource_group_name="rg", service_name="gateway", product_id="run-owned-product",
            if_match="*", delete_subscriptions=True,
        )
        self.assertFalse(owned)

    def test_failed_cleanup_retains_ownership_for_retry(self):
        apim = SimpleNamespace(resource_group_name="rg", apim_resource_name="gateway", client=Mock())
        apim.client.product.delete.side_effect = RuntimeError("mock deletion failure")
        owned = {"run-owned-product"}
        with redirect_stdout(io.StringIO()), self.assertRaises(RuntimeError):
            cleanup_products(apim, owned, enabled=True)
        self.assertEqual(owned, {"run-owned-product"})

    def test_manifest_contains_artifacts_and_ownership_not_credentials(self):
        directory = ROOT / "validation" / ".runs" / "scenario" / "run"
        artifact = directory / "access" / "main.bicepparam"
        with patch.object(Path, "rglob", return_value=[artifact]), patch.object(Path, "write_text") as write:
            with redirect_stdout(io.StringIO()):
                path = save_manifest(directory, synthetic_context(),
                    SimpleNamespace(apim_resource_name="gateway"), {"owned-product"})
        manifest = json.loads(write.call_args.args[0])
        self.assertEqual(path, directory / "manifest.json")
        self.assertEqual(manifest["owned_products"], ["owned-product"])
        self.assertEqual(manifest["artifacts"], [str(Path("access") / "main.bicepparam")])
        self.assertNotIn("synthetic-not-for-output", write.call_args.args[0])
        self.assertFalse(manifest["cleanup_enabled_by_default"])


class NotebookExecutionTests(unittest.TestCase):
    def blocking_result(self, body, *, status=400, transport_error=None, should_block=True):
        namespace = self.namespace()
        namespace.update({
            "pii_blocking_test_payloads": [{
                "name": "Synthetic credit-card detection", "should_block": should_block,
                "expected_pii": ["CREDIT_CARD"],
                "payload": {"model": "future-model", "messages": []},
            }],
            "chat_completions_url": "https://gateway/models/chat/completions",
            "blocking_api_key": "fixture-only-key",
            "transport": Mock(),
        })
        namespace["transport"].request.return_value = SimpleNamespace(
            json_body=body, status_code=status, error=transport_error, duration=0.1,
        )
        source = notebook_cell("pii-processing", "blocking_test_results = []")
        with redirect_stdout(io.StringIO()):
            exec(source, namespace)
        return namespace["run"], namespace["blocking_test_results"]

    def test_successful_blocking_accepts_category_labels_without_placeholder_matching(self):
        for categories in ("CREDIT", "CreditCard", "Person, Email", ["Person", "CREDIT"], None):
            with self.subTest(categories=categories):
                run, results = self.blocking_result({"error": {
                    "code": "PII_DETECTED", "entityCount": 1, "detectedCategories": categories,
                }})
                self.assertEqual(run.results[-1].status, "PASS")
                self.assertTrue(results[-1]["test_passed"])
                self.assertEqual(run.results[-1].evidence["detected_categories"], categories)
                self.assertEqual(run.results[-1].evidence["entity_count"], 1)
                with redirect_stdout(io.StringIO()):
                    run.finish()

    def test_generic_errors_or_absent_detection_do_not_pass_blocking(self):
        for body, status in (
            ({"error": {"code": "OTHER_ERROR", "entityCount": 1}}, 400),
            ({"error": {"code": "PII_DETECTED", "entityCount": 1}}, 403),
            ({"error": {"code": "PII_DETECTED", "entityCount": 0}}, 400),
            ({"error": {"code": "PII_DETECTED", "entityCount": -1}}, 400),
            ({"error": {"code": "PII_DETECTED", "entityCount": True}}, 400),
            ({"error": {"code": "PII_DETECTED", "entityCount": "1"}}, 400),
            ({"error": {"code": "PII_DETECTED"}}, 400),
            ({"error": "PII_DETECTED"}, 400),
            ({"error": None}, 400),
            (None, 400),
        ):
            with self.subTest(body=body, status=status):
                run, results = self.blocking_result(body, status=status)
                self.assertEqual(run.results[-1].status, "FAIL")
                self.assertFalse(results[-1]["success"])

    def test_transport_failure_is_reflected_in_both_result_and_summary(self):
        run, results = self.blocking_result({"error": {
            "code": "PII_DETECTED", "entityCount": 1, "detectedCategories": "CREDIT",
        }}, transport_error="connection failure")
        self.assertEqual(run.results[-1].status, "FAIL")
        self.assertFalse(results[-1]["test_passed"])
        self.assertFalse(results[-1]["success"])

    def test_no_pii_control_still_requires_a_successful_completion(self):
        run, results = self.blocking_result(
            {"choices": [{"message": {"content": "A safe response"}}]}, status=200, should_block=False,
        )
        self.assertEqual(run.results[-1].status, "PASS")
        self.assertTrue(results[-1]["success"])
        run, _ = self.blocking_result({"choices": []}, status=200, should_block=False)
        self.assertEqual(run.results[-1].status, "FAIL")

    def namespace(self):
        apim = Mock()
        utils = Mock()
        utils.notebook_step = notebook_utils.notebook_step
        utils.require_inputs = notebook_utils.require_inputs
        utils.require_capabilities = notebook_utils.require_capabilities
        utils.run.side_effect = AssertionError("Unexpected CLI boundary in a provisioning unit test.")
        apim.apim_resource_name = "gateway"
        apim.client.api.list_by_service.return_value = [
            SimpleNamespace(name=name) for name in
            ["universal-llm-api", "azure-openai-api", "unified-ai-api", "weather-api"]
        ]
        return {
            "context": synthetic_context(), "apimClientTool": apim, "utils": utils,
            "governance_hub_resource_group": "rg", "subscription_id": "subscription",
            "location": "eastus", "apim_name": "gateway", "run_id": "offline",
            "run_dir": ROOT / "validation" / ".runs" / "mocked",
            "repo_root": ROOT, "run": ValidationRun("offline"),
            "access_parameters": access_parameters, "access_policy": access_policy,
            "policy_xml": policy_xml, "normalize_policy_xml": policy_xml,
            "contract_identity": contract_identity,
            "write_parameters": Mock(return_value=ROOT / "mocked.bicepparam"),
            "preview": Mock(return_value="using 'main.bicep'"),
            "deploy_contract": Mock(return_value=outputs()),
            "preexisting_products": set(), "owned_products": set(),
            "use_keyvault_integration": False, "keyvault_subscription_id": "",
            "keyvault_resource_group": "", "keyvault_name": "",
            "contract_business_unit": "Tests", "contract_use_case_name": "Run",
            "contract_environment": "DEV", "allowed_models_list": ["future-model"],
            "target_model": "future-model", "use_access_contract_kv": False,
            "image_ready": True, "affinity_ready": True,
            "access_contract_kv_name": "", "access_contract_kv_subscription_id": "",
            "access_contract_kv_resource_group": "", "completion_text": completion_text,
            "assets": [
                {"assetType": "mcp-from-api", "name": "weather-tool", "sourceApiName": "weather-api",
                 "forwardSubscriptionKeyToSource": True},
                {"assetType": "a2a", "name": "hr-agent"},
            ],
        }

    def test_five_notebooks_preview_then_deploy_and_lookup_exact_credentials(self):
        cases = [
            ("pii-processing", "masking", "pii_masking_contract", "pii_masking_policy"),
            ("jwt-authentication", "jwt", "jwt_contract", "jwt_product_policy"),
            ("publish-contract", "publish_access", None, None),
            ("image-models", "image", None, None),
            ("session-affinity", "affinity", None, None),
        ]
        for scenario, prefix, contract_name, policy_name in cases:
            with self.subTest(scenario=scenario):
                namespace = self.namespace()
                if contract_name:
                    namespace[contract_name] = synthetic_contract()
                    namespace[policy_name] = access_policy(["future-model"], 5000, 100000, "Monthly")
                with redirect_stdout(io.StringIO()):
                    exec(notebook_cell(scenario, prefix + "_parameters ="), namespace)
                    namespace["deploy_contract"].assert_not_called()
                    namespace["apimClientTool"].get_subscription_key.assert_not_called()
                    exec(notebook_cell(scenario, prefix + "_outputs ="), namespace)
                    # Images/affinity keep credential lookup in the following teaching cell.
                    if scenario in ("image-models", "session-affinity"):
                        namespace["gateway_url"] = "https://gateway"
                        namespace["unified_api"] = {"url": "https://gateway/unified-ai"}
                        if scenario == "session-affinity":
                            # Execute only the credential statement, before live pool inspection.
                            source = notebook_cell(scenario, "api_key = apimClientTool.get_subscription_key(")
                            statement = next(
                                node for node in ast.walk(ast.parse(source))
                                if isinstance(node, ast.Assign)
                                and any(isinstance(target, ast.Name) and target.id == "api_key"
                                        for target in node.targets)
                                and isinstance(node.value, ast.Call)
                            )
                            exec(compile(ast.Module([statement], type_ignores=[]), "<credential>", "exec"), namespace)
                        else:
                            exec(notebook_cell(scenario, "api_key = apimClientTool.get_subscription_key("), namespace)
                namespace["write_parameters"].assert_called_once()
                namespace["preview"].assert_called_once_with(ROOT / "mocked.bicepparam")
                namespace["deploy_contract"].assert_called_once()
                namespace["apimClientTool"].get_subscription_key.assert_called_once_with("actual-subscription")
                namespace["apimClientTool"].initialize.assert_not_called()
                self.assertEqual(namespace["owned_products"], {"actual-product"})
                parameters = namespace["write_parameters"].call_args.args[1]
                self.assertIn("services", parameters)
                ET.fromstring(parameters["services"][0]["policyXml"])
                if scenario == "publish-contract":
                    self.assertIn("weather-api", parameters["apiNameMapping"]["MULTI"])
                    self.assertEqual(len(parameters["services"][0]["assetEndpoints"]), 5)

    def test_deployment_failure_never_falls_back_to_an_existing_subscription(self):
        namespace = self.namespace()
        namespace["jwt_contract"] = synthetic_contract()
        namespace["jwt_params_file"] = ROOT / "mocked.bicepparam"
        namespace["deploy_contract"].side_effect = RuntimeError("mock deployment failed")
        with self.assertRaises(RuntimeError):
            exec(notebook_cell("jwt-authentication", "jwt_outputs ="), namespace)
        namespace["apimClientTool"].get_subscription_key.assert_not_called()
        self.assertFalse(namespace["owned_products"])

    def test_missing_enabled_foundry_coordinates_block_before_provisioning(self):
        namespace = self.namespace()
        namespace.update({
            "ValidationContext": SimpleNamespace(load=Mock(return_value=namespace["context"])),
            "ValidationRun": ValidationRun, "ValidationBlocked": ValidationBlocked,
            "RequestTransport": Mock(), "overrides": {}, "environment": None,
            "operation_overrides": None, "skipped_models": None,
            "init_from_azd": False, "enable_a2a_asset": True,
            "foundry_account_name": "", "foundry_project_name": "", "foundry_agent_name": "",
            "foundry_project_endpoint": "",
            "app_insights_name_override": None,
        })
        with patch.object(Path, "mkdir"), redirect_stdout(io.StringIO()), self.assertRaises(ValueError) as raised:
            exec(notebook_cell("publish-contract", 'run = ValidationRun("publish-contract")'), namespace)
        for label in ("a2a.foundry_account_name", "a2a.foundry_project_name", "a2a.foundry_agent_name"):
            self.assertIn(label, str(raised.exception))
        self.assertFalse(namespace["run"].results)
        namespace["write_parameters"].assert_not_called()
        namespace["deploy_contract"].assert_not_called()

    def test_missing_no_role_fixture_blocks_without_an_invalid_token_fallback(self):
        namespace = self.namespace()
        namespace.update({
            "no_role_token_fixture": "", "active_token": "genuine-role-bearing-fixture",
            "token_claims": lambda token: {"roles": ["Model.Invoke"], "exp": 9999999999},
            "api_endpoints": [{"name": "models"}], "time": time, "transport": Mock(),
        })
        exec(notebook_cell("jwt-authentication", "no_role_token = no_role_token_fixture"), namespace)
        self.assertEqual(namespace["run"].results[-1].status, "BLOCKED")
        namespace["transport"].request.assert_not_called()
        with redirect_stdout(io.StringIO()), self.assertRaises(ValidationError):
            namespace["run"].finish()

    def test_pii_success_without_correlated_state_evidence_blocks(self):
        namespace = self.namespace()
        namespace.update({"re": re, "json": json, "model_name": "future-model"})
        notebook_functions(notebook_cell("pii-processing", "def verify_pii_state"), namespace)
        pending = {"case": "mask", "marker": "run-marker", "payload": {"messages": []},
                   "content": "Alice", "expected_pii": [], "large": False}
        namespace["verify_pii_state"](pending, [])
        self.assertEqual(namespace["run"].results[-1].status, "BLOCKED")
        with redirect_stdout(io.StringIO()), self.assertRaises(ValidationError):
            namespace["run"].finish()

    def test_pii_proof_requires_both_actual_masking_and_restoration(self):
        namespace = self.namespace()
        namespace.update({"re": re, "json": json, "model_name": "future-model"})
        notebook_functions(notebook_cell("pii-processing", "def verify_pii_state"), namespace)
        payload = {"messages": [{"role": "user", "content": "run-marker Alice"}]}
        pending = {"case": "mask", "marker": "run-marker", "payload": payload,
                   "content": "Alice", "expected_pii": ["Person"], "large": False}
        record = {"id": "evidence", "context": {"api": {"content": {
            "originalRequest": json.dumps(payload),
            "anonymizedRequest": json.dumps(payload).replace("Alice", "<Person_0>"),
            "originalResponse": json.dumps({"choices": [{"message": {"content": "<Person_0>"}}]}),
            "deanonymizedResponse": json.dumps({"choices": [{"message": {"content": "Alice"}}]}),
        }}}, "mappings": [{"original": "Alice", "placeholder": "<Person_0>"}],
            "entityCategories": {"Person": 1}}
        namespace["verify_pii_state"](pending, [record])
        self.assertEqual(namespace["run"].results[-1].status, "PASS")
        record["context"]["api"]["content"]["anonymizedRequest"] = json.dumps(payload)
        namespace["verify_pii_state"](pending, [record])
        self.assertEqual(namespace["run"].results[-1].status, "FAIL")

    def test_publish_malformed_http_success_fails_without_resetting_earlier_results(self):
        namespace = self.namespace()
        namespace.update({"requests": Mock(), "results": {"earlier-kv-check": False}})
        notebook_functions(notebook_cell("publish-contract", "def validate_mcp"), namespace)
        namespace["mcp_call"] = Mock(return_value=(SimpleNamespace(status_code=200, headers={}), {}))
        self.assertFalse(namespace["validate_mcp"]("https://gateway/mcp", "synthetic-key", "test"))
        self.assertEqual(namespace["results"], {"earlier-kv-check": False})
        self.assertTrue(all(result.status == "FAIL" for result in namespace["run"].results))

    def test_role_policy_keeps_real_jwt_role_and_model_controls(self):
        namespace = self.namespace()
        namespace.update({"role_contract": synthetic_contract(), "model_name": "future-model"})
        with redirect_stdout(io.StringIO()):
            exec(notebook_cell("jwt-authentication", "role_product_policy ="), namespace)
        root = ET.fromstring(namespace["role_product_policy"])
        self.assertEqual(root.find(".//set-variable[@name='jwtRequired']").get("value"), "true")
        self.assertEqual(root.find(".//set-variable[@name='requiredRoles']").get("value"), "Model.Invoke")
        self.assertEqual(root.find(".//set-variable[@name='allowedModels']").get("value"), "future-model")
        self.assertIsNotNone(root.find(".//include-fragment[@fragment-id='validate-model-access']"))
        namespace["deploy_contract"].assert_not_called()

    def test_affinity_equal_region_cannot_replace_stable_cookie_evidence(self):
        source = notebook_cell("session-affinity", "by_session = defaultdict")
        for cookies, expected in [(["opaque"] * 3, "PASS"), ([""] * 3, "FAIL"), (["a", "b", "b"], "FAIL")]:
            with self.subTest(cookies=cookies):
                records = [{
                    "session": 1, "request": index + 1, "response_id": f"response-{index}",
                    "previous_response_id": "" if index == 0 else "response-0",
                    "status": 200, "output_text": ["acknowledged", "Ada", "14"][index],
                    "cookie": cookie, "backend_pool": "pool", "backend_region": "eastus",
                } for index, cookie in enumerate(cookies)]
                namespace = {
                    "all_records": records, "num_sessions": 1, "requests_per_session": 3,
                    "run": ValidationRun("affinity"), "eligible_live_pools": {"pool": {"east", "west"}},
                    "serving_backends": ["east", "west"], "target_model": "future-model",
                    "utils": notebook_utils,
                    "affinity_ready": True,
                }
                exec(source, namespace)
                result = next(result for result in namespace["run"].results if result.case == "session/1")
                self.assertEqual(result.status, expected)

    def test_image_http_success_requires_decodable_nonempty_image_data(self):
        from PIL import Image, UnidentifiedImageError

        namespace = {"base64": base64, "requests": Mock(), "run_dir": ROOT / "mocked-images", "re": re}
        notebook_functions(notebook_cell("image-models", "def decoded_image"), namespace)
        response = Mock()
        response.json.return_value = {"data": [{"b64_json": base64.b64encode(b"not an image").decode()}]}
        with self.assertRaises(UnidentifiedImageError):
            namespace["decoded_image"](response, "invalid")
        image_data = io.BytesIO()
        Image.new("RGB", (2, 2), "red").save(image_data, format="PNG")
        response.json.return_value = {"data": [{"b64_json": base64.b64encode(image_data.getvalue()).decode()}]}
        with patch.object(Image.Image, "save") as save:
            path = namespace["decoded_image"](response, "valid")
        self.assertEqual(path, str(ROOT / "mocked-images" / "valid.png"))
        save.assert_called_once()
        namespace["requests"].get.assert_not_called()


if __name__ == "__main__":
    unittest.main()
