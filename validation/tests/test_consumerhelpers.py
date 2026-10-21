"""Offline regression coverage for consumer plumbing and visible notebook cells."""

import ast
import contextlib
import io
import json
from pathlib import Path
import shutil
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))

import apimtools
import consumerhelpers as helpers
import contracttools
import requests
import validationtools
from contracttools import access_policy
from validationtools import HTTPResult, ModelCatalog, ValidationError


class ConsumerHelperTests(unittest.TestCase):
    def setUp(self):
        self.target = {
            "subscriptionId": "fixture-subscription",
            "resourceGroupName": "fixture-rg",
            "name": "fixture-apim",
        }
        self.source = {
            "llmBackendConfig": [{
                "backendId": "existing",
                "backendType": "ai-foundry",
                "protocol": "openai-compat",
                "supportedModels": [{
                    "name": "arbitrary-future-model", "sessionAwareModel": True,
                    "modelPath": "provider-path",
                }],
                "circuitBreaker": {"enabled": False},
                "sessionAffinity": {"cookieName": "keep-cookie"},
            }],
            "modelAliases": [{
                "name": "existing-alias", "models": ["arbitrary-future-model"],
                "strategy": "priority",
            }],
            "configureCircuitBreaker": False,
        }

    def test_access_provisioning_preserves_visible_policy_and_api_grants(self):
        context = SimpleNamespace(config={
            "subscription_id": self.target["subscriptionId"],
            "resource_group": self.target["resourceGroupName"],
        })
        apim = SimpleNamespace(apim_resource_name=self.target["name"])
        use_case = {"businessUnit": "Fixture", "useCaseName": "Unique", "environment": "DEV"}
        api_names = ["universal-llm-api", "unified-ai-api"]
        policy = access_policy(
            ["arbitrary-future-model"], 500, 1200, "Hourly",
            inbound_extra='<set-variable name="enableResponseHeaders" value="@(true)" />',
        )
        with patch.object(helpers, "prepare_artifact", return_value="artifact") as prepare:
            result = helpers.access_artifact(
                ROOT, ROOT / "validation" / ".runs" / "fixture",
                context, apim, use_case, api_names, policy,
            )
        self.assertEqual(result, "artifact")
        args, kwargs = prepare.call_args
        self.assertEqual(args[0], ROOT / "bicep" / "infra" / "citadel-access-contracts" / "main.bicep")
        parameters = args[1]
        self.assertEqual(parameters["apim"], self.target)
        self.assertEqual(parameters["useCase"], use_case)
        self.assertEqual(parameters["apiNameMapping"], {"LLM": api_names})
        self.assertFalse(parameters["useTargetAzureKeyVault"])
        self.assertFalse(parameters["useTargetFoundry"])
        self.assertEqual(parameters["services"][0]["policyXml"], policy)
        self.assertEqual(kwargs["policies"], {"ai-product-policy.xml": policy})
        inbound = ET.fromstring(policy).find("inbound")
        fragments = [node.get("fragment-id") for node in inbound.findall("include-fragment")]
        self.assertEqual(fragments[:2], ["set-llm-requested-model", "validate-model-access"])
        limit = inbound.find("llm-token-limit")
        self.assertEqual(limit.get("tokens-per-minute"), "500")
        self.assertEqual(limit.get("token-quota"), "1200")
        self.assertEqual(limit.get("token-quota-period"), "Hourly")

    def test_exact_raw_output_subscription_and_no_fallback(self):
        outputs = {
            "products": {"value": [{"productId": "owned"}]},
            "subscriptions": {"value": [
                {"productId": "other", "name": "wrong"},
                {"productId": "owned", "name": "exact"},
            ]},
        }
        self.assertEqual(helpers.contract_identifiers(outputs, "owned"), ("owned", "exact"))
        with self.assertRaises(RuntimeError):
            helpers.contract_identifiers(outputs, "absent")
        outputs["subscriptions"]["value"].append({"productId": "owned", "name": "ambiguous"})
        with self.assertRaises(RuntimeError):
            helpers.contract_identifiers(outputs, "owned")

    def test_lossless_backend_merge_without_mutating_source(self):
        addition = {
            "backendId": "new", "backendType": "anthropic",
            "authType": "api-key-anthropic",
            "authConfig": {"namedValueKey": "new-key", "keyVaultSecretUri": "https://fixture.vault.azure.net/secrets/provider"},
            "supportedModels": [{"name": "future-native-model"}],
        }
        snapshot = json.loads(json.dumps(self.source))
        merged = helpers.complete_backend_parameters(self.source, [addition], confirmed_complete=True)
        self.assertEqual(merged["llmBackendConfig"][0], snapshot["llmBackendConfig"][0])
        self.assertEqual(merged["modelAliases"], snapshot["modelAliases"])
        self.assertFalse(merged["configureCircuitBreaker"])
        merged["llmBackendConfig"][0]["sessionAffinity"]["cookieName"] = "edited"
        self.assertEqual(self.source, snapshot)

    def test_missing_source_or_confirmation_blocks(self):
        for flag in (False, "false", 1, None):
            with self.subTest(flag=flag), self.assertRaises(ValueError):
                helpers.complete_backend_parameters(self.source, [], confirmed_complete=flag)
        for source in ({}, {"llmBackendConfig": self.source["llmBackendConfig"]}):
            with self.subTest(source=source), self.assertRaises(ValueError):
                helpers.complete_backend_parameters(source, [], confirmed_complete=True)

    def test_replacements_duplicates_and_inline_secrets_are_rejected(self):
        with self.assertRaises(ValueError):
            helpers.complete_backend_parameters(
                self.source, [self.source["llmBackendConfig"][0]], confirmed_complete=True,
            )
        duplicate_aliases = dict(self.source, modelAliases=self.source["modelAliases"] * 2)
        with self.assertRaises(ValueError):
            helpers.complete_backend_parameters(duplicate_aliases, [], confirmed_complete=True)
        addition = {
            "backendId": "unsafe", "authType": "api-key-bearer",
            "authConfig": {"secretValue": "never-persist"},
        }
        with self.assertRaises(ValueError):
            helpers.complete_backend_parameters(self.source, [addition], confirmed_complete=True)

    def test_business_unit_handoff_normalizes_connection_metadata(self):
        handoff = {"contracts": [{
            "business_unit": "HR", "product_id": "unique", "subscription_name": "exact",
            "allowed_models": ["arbitrary-future-model"],
            "connections": [{
                "connectionName": "connection", "foundryAccount": "account", "foundryProject": "project",
            }],
        }]}
        with patch.object(Path, "read_text", return_value=json.dumps(handoff)):
            records = helpers.load_contract_manifest("unused")
        self.assertEqual(records["HR-ChatAgent"]["connection_name"], "connection")
        self.assertEqual(
            records["HR-ChatAgent"]["project_endpoint"],
            "https://account.services.ai.azure.com/api/projects/project",
        )

    def test_missing_or_secret_handoff_cannot_be_used(self):
        for handoff in (
            {"contracts": [{"business_unit": "Sales"}]},
            {"contracts": {"Sales-Assistant": {
                "product_id": "owned", "subscription_name": "exact",
                "allowed_models": ["arbitrary"], "api_key": "never-persist",
            }}},
        ):
            with patch.object(Path, "read_text", return_value=json.dumps(handoff)):
                with self.assertRaises(ValueError):
                    helpers.load_contract_manifest("unused")

    def test_review_of_edited_backend_parameters_preserves_predecessors(self):
        def artifact(values):
            return SimpleNamespace(compile=lambda: {
                "parametersJson": json.dumps({
                    "parameters": {key: {"value": value} for key, value in values.items()},
                }),
            })
        values = dict(self.source, apim=self.target)
        self.assertEqual(
            helpers.review_backend_artifact(artifact(values), self.source, self.target, {"existing"}), values,
        )
        for changes in (
            {"apim": dict(self.target, name="another-hub")},
            {"llmBackendConfig": []}, {"modelAliases": []}, {"configureCircuitBreaker": True},
        ):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                helpers.review_backend_artifact(
                    artifact(dict(values, **changes)), self.source, self.target, {"existing"},
                )

    def test_cli_is_mocked_checked_private_and_handles_empty_deletion(self):
        with patch.object(helpers.shutil, "which", return_value="az.exe"):
            with patch.object(helpers.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout="")) as run:
                self.assertIsNone(helpers.cli_json("resource", "delete", "--ids", "owned"))
                self.assertFalse(run.call_args.kwargs["shell"])
                self.assertEqual(run.call_args.kwargs["encoding"], "utf-8")
            with patch.object(helpers.subprocess, "run", return_value=SimpleNamespace(returncode=1, stdout="secret", stderr="secret")):
                with self.assertRaises(RuntimeError) as raised:
                    helpers.cli_json("resource", "show")
                self.assertNotIn("secret", str(raised.exception))
            with patch.object(helpers.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout="not-json")):
                with self.assertRaises(RuntimeError):
                    helpers.cli_json("resource", "show")

    def test_response_extractors_do_not_fabricate_content_or_errors(self):
        for body in (None, [], {}, {"choices": []}):
            self.assertEqual(helpers.chat_content(body), "")
        self.assertEqual(helpers.chat_content({"choices": [{"message": {"content": "OK"}}]}), "OK")
        self.assertEqual(helpers.error_code({"error": {"code": "unauthorized_model_access"}}), "unauthorized_model_access")
        self.assertEqual(helpers.error_code({"error": "not a policy error"}), "")


class UnifiedNotebookWorkflowTests(unittest.TestCase):
    """Execute real visible cells, with all cloud, artifact and HTTP boundaries mocked."""

    def run_workflow(self, capabilities=None, chat_text="4", stream_complete=True,
                     response_get_status=200, response_delete_status=200):
        model = "arbitrary-future-model"
        backends = [{
            "backendId": "fixture", "backendType": "ai-foundry", "protocol": "openai-compat",
            "supportedModels": [{"name": model, "modelFormat": "OpenAI"}],
        }]
        config = {
            "resource_group": "fixture-rg", "subscription_id": "fixture-subscription",
            "location": "fixture-region", "apim_name": "fixture-apim", "llm_backends": backends,
            "capabilities": {model: capabilities if capabilities is not None else ["chat", "responses", "streaming"]},
        }
        context = SimpleNamespace(
            config=config, account={"id": config["subscription_id"]},
            catalog=ModelCatalog(backends, config["capabilities"]),
        )
        namespace = {}

        class FakeAPIM:
            apim_resource_name = "fixture-apim"
            apim_service_id = "/fixture/apim"

            def initialize_context(self, account, enumerate_subscriptions=False):
                self.asserted_account = account
                if enumerate_subscriptions:
                    raise AssertionError("Subscription enumeration is forbidden.")

            def discover_api_exact(self, path):
                return {"url": "https://gateway.example/" + path, "path": path, "id": path, "name": path}

            def get_subscription_key(self, name):
                if name != namespace["product_id"] + "-SUB-01":
                    raise AssertionError("Only the exact subscription key may be retrieved.")
                return "fixture-key"

        class FakeArtifact:
            params_file = Path("fixture.bicepparam")

            def preview(self):
                return "fixture parameter preview"

            def record_resource(self, identifier, *, created):
                if not created or not identifier.endswith(namespace["product_id"]):
                    raise AssertionError("Only the run-owned product may be recorded.")

            def cleanup_candidates(self):
                return []

        def deploy(*args, **kwargs):
            product = namespace["product_id"]
            return {
                "products": {"value": [{"productId": product}]},
                "subscriptions": {"value": [{"productId": product, "name": product + "-SUB-01"}]},
            }

        def http(transport, method, url, **kwargs):
            headers = kwargs.get("headers") or {}
            body = kwargs.get("json") or {}
            status = 200
            response = {"choices": [{"message": {"content": chat_text}}]}
            if headers.get("api-key") != "fixture-key" or "/unified-ai/" not in url:
                status, response = 401, {"message": "Access denied due to invalid subscription key."}
            elif "nonexistent-validation" in url:
                status, response = 404, {"error": {"code": "deployment_not_found"}}
            elif any(segment in url for segment in ("invalid-path", "some/random", "v2/openai")):
                status, response = 403, {"error": {"code": "PathNotAllowed"}}
            elif body.get("model") == "unauthorized-validation-model-xyz":
                status, response = 403, {"error": {"code": "unauthorized_model_access"}}
            elif "/deployments" in url and method == "GET":
                response = {"name": model} if url.endswith("/" + model) else {"value": [{"name": model}]}
            elif "/responses" in url:
                response = {"deleted": True} if method == "DELETE" else {
                    "id": "response-fixture", "status": "completed", "output": [{"type": "message"}],
                }
                if method == "GET" and response_get_status != 200:
                    status, response = response_get_status, {"error": {"code": "retrieval-error"}}
                if method == "DELETE" and response_delete_status != 200:
                    status, response = response_delete_status, {"error": {"code": "delete-error"}}
            api_type = "responses" if "/responses" in url else "inference" if "/models/chat" in url else "openai"
            response_headers = {key: "fixture" for key in (
                "UAIG-Auth-Type", "UAIG-User-Id", "UAIG-Subscription", "UAIG-Processed-Path",
                "UAIG-API-Version", "UAIG-Backend", "UAIG-Final-Path",
            )}
            response_headers.update({
                "UAIG-Model-Id": model, "UAIG-API-Type": api_type,
                "UAIG-Is-Streaming": "false", "UAIG-Cache-Operation": "cache-hit",
            })
            return HTTPResult(status, response, json.dumps(response), response_headers, b"fixture", 0.01)

        class Stream:
            status_code = 200
            headers = {"Content-Type": "text/event-stream", "UAIG-Is-Streaming": "true"}

            def __enter__(self):
                return self

            def __exit__(self, *args):
                pass

            def iter_lines(self, **kwargs):
                events = ['data: {"choices":[{"delta":{"content":"OK"}}]}', ""]
                if stream_complete:
                    events.append("data: [DONE]")
                return iter(events)

        notebook = json.loads((ROOT / "validation" / "citadel-unified-ai-api-tests.ipynb").read_text(encoding="utf-8"))
        error = None
        try:
            with contextlib.ExitStack() as stack:
                stack.enter_context(patch.object(validationtools.ValidationContext, "load", return_value=context))
                stack.enter_context(patch.object(apimtools, "APIMClientTool", return_value=FakeAPIM()))
                stack.enter_context(patch.object(helpers, "access_artifact", return_value=FakeArtifact()))
                stack.enter_context(patch.object(contracttools, "deploy_contract", side_effect=deploy))
                stack.enter_context(patch.object(validationtools.RequestTransport, "request", http))
                stack.enter_context(patch.object(requests, "post", return_value=Stream()))
                stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
                try:
                    for index, cell in enumerate(notebook["cells"]):
                        if cell["cell_type"] == "code":
                            exec(compile(
                                "".join(cell["source"]), f"unified-cell-{index}", "exec",
                                flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT,
                            ), namespace)
                except ValidationError as exc:
                    error = exc
            return namespace["run"].results, error
        finally:
            if namespace.get("run_dir"):
                shutil.rmtree(namespace["run_dir"], ignore_errors=True)

    def test_complete_visible_workflow_with_mocked_provisioning_and_requests(self):
        results, error = self.run_workflow()
        self.assertIsNone(error)
        self.assertTrue(all(result.status in ("PASS", "SKIP") for result in results))
        self.assertGreaterEqual(sum(result.status == "PASS" for result in results), 24)
        self.assertTrue(any(result.case == "streaming/complete" and result.status == "PASS" for result in results))

    def test_status_200_without_content_cannot_pass_the_final_verdict(self):
        results, error = self.run_workflow(chat_text="")
        self.assertIsInstance(error, ValidationError)
        self.assertTrue(any(result.case == "openai/chat" and result.status == "FAIL" for result in results))
        self.assertTrue(any(result.status == "PASS" for result in results))

    def test_missing_optional_streaming_capability_skips_without_customization(self):
        results, error = self.run_workflow(capabilities=["chat", "responses"])
        self.assertIsNone(error)
        self.assertTrue(any(result.case == "streaming/selection" and result.status == "SKIP" for result in results))
        self.assertTrue(any(result.case == "streaming/complete" and result.status == "SKIP" for result in results))

    def test_incomplete_sse_without_done_cannot_pass(self):
        results, error = self.run_workflow(stream_complete=False)
        self.assertIsInstance(error, ValidationError)
        self.assertTrue(any(result.case == "streaming/complete" and result.status == "FAIL" for result in results))

    def test_responses_get_404_is_warning_without_failing_the_run(self):
        results, error = self.run_workflow(response_get_status=404)
        self.assertIsNone(error)
        self.assertEqual([r.status for r in results if r.case == "responses/get"], ["SKIP"])
        self.assertTrue(any(r.case == "responses/delete" and r.status == "PASS" for r in results))

    def test_other_get_errors_and_delete_404_still_fail(self):
        for options, case in (
            ({"response_get_status": 401}, "responses/get"),
            ({"response_get_status": 500}, "responses/get"),
            ({"response_delete_status": 404}, "responses/delete"),
        ):
            with self.subTest(options=options):
                results, error = self.run_workflow(**options)
                self.assertIsInstance(error, ValidationError)
                self.assertTrue(any(r.case == case and r.status == "FAIL" for r in results))


if __name__ == "__main__":
    unittest.main()
