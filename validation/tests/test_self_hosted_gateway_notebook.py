"""Execute the self-hosted notebook offline, mocking only cloud/HTTP boundaries."""
import contextlib
import io
import itertools
import json
import os
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))
import requests
import contracttools
from validationtools import ModelCatalog, ValidationContext, ValidationError

NOTEBOOK = ROOT / "validation" / "citadel-self-hosted-gateway-tests.ipynb"
CELLS = ["".join(cell["source"]) for cell in json.loads(NOTEBOOK.read_text(encoding="utf-8"))["cells"]
         if cell["cell_type"] == "code"]
SWITCHES = ("enable_token_limit", "enable_model_rbac", "enable_content_safety", "enable_pii_processing")


def response(status, body, headers=None):
    result = requests.Response()
    result.status_code = status
    result._content = json.dumps(body).encode()
    result.headers.update(headers or {})
    result.url = "https://edge.example/models"
    return result


class SelfHostedGatewayNotebookTests(unittest.TestCase):
    def setUp(self):
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.directory = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.stack.enter_context(patch.dict(os.environ, {
            "VALIDATION_SELF_HOSTED_GATEWAY_URL": "",
            "VALIDATION_SELF_HOSTED_GATEWAY_ID": "",
        }))
        self.namespace = {}
        self.execute(0)
        self.namespace.update(self_hosted_gateway_url="https://edge.example", self_hosted_gateway_id="edge-fixture")
        backends = [{
            "backendId": "fixture", "backendType": "ai-foundry",
            "supportedModels": [{"name": name} for name in (
                "gpt-alpha", "GPT-beta", "gpt-image-example", "gpt-audio-example",
                "gpt-realtime-example", "text-embedding-example", "other-chat",
            )],
        }]
        self.context = SimpleNamespace(
            config={"subscription_id": "fixture-sub", "resource_group": "fixture-rg",
                    "location": "fixture-region", "apim_name": "fixture-apim", "llm_backends": backends},
            catalog=ModelCatalog(backends), account={"id": "fixture-sub"}, azd_snapshot={},
        )
        self.apim = Mock()
        self.apim.resource_group_name = "fixture-rg"
        self.apim.apim_resource_name = "fixture-apim"
        self.apim.apim_resource_gateway_url = "https://managed.example"
        self.apim.discover_api_exact.return_value = {
            "name": "universal-llm-api", "path": "models", "url": "https://managed.example/models",
        }
        self.apim.client.gateway_api.list_by_service.return_value = [SimpleNamespace(name="universal-llm-api")]
        self.apim.client.product.list_by_service.return_value = []
        self.namespace["APIMClientTool"] = Mock(return_value=self.apim)
        self.stack.enter_context(patch.object(ValidationContext, "load", return_value=self.context))

    def execute(self, index):
        exec(compile(CELLS[index], f"{NOTEBOOK.name}:{index}", "exec"), self.namespace)

    def initialize(self):
        self.execute(1)
        self.namespace["run_dir"] = self.directory / self.namespace["run_id"]

    def preview(self):
        self.initialize()
        self.execute(2)
        return ET.fromstring(self.namespace["contract_policy"])

    def deploy(self):
        self.preview()
        self.apim.client.product_policy.get.return_value.value = self.namespace["contract_policy"]
        outputs = {"products": {"value": [{"productId": "owned-product"}]},
                   "subscriptions": {"value": [{"productId": "owned-product", "name": "owned-subscription"}]}}
        self.stack.enter_context(patch.object(contracttools, "deploy_contract", return_value=outputs))
        self.apim.get_subscription_key.return_value = "fixture-key-not-persisted"
        self.execute(3)

    def session(self):
        session = MagicMock()
        session.__enter__.return_value = session
        session.headers = {}
        self.stack.enter_context(patch.object(requests, "Session", return_value=session))
        return session

    def discover(self, session, names=None):
        names = self.namespace["selected_models"] if names is None else names
        # Deployment IDs identify backends; selection must use the name.
        session.get.return_value = response(200, {"value": [{"id": "backend-id", "name": name} for name in names]})
        self.execute(4)

    def chat_response(self, **updates):
        headers = {"x-citadel-gateway-id": "edge-fixture", "x-citadel-contract-run": self.namespace["run_id"],
                   "x-citadel-capacity-remaining": "999990", "x-citadel-safety-checked": "true",
                   "x-citadel-pii-masked": "true"}
        headers.update(updates)
        return response(200, {"choices": [{"message": {"content": "4"}}],
                              "usage": {"total_tokens": 10}}, headers)

    def test_all_switch_combinations_remove_only_disabled_contract_features(self):
        for flags in itertools.product((True, False), repeat=4):
            with self.subTest(flags=flags):
                self.namespace.update(dict(zip(SWITCHES, flags)))
                policy = self.preview()
                chat = policy.find("./inbound/choose/when")
                self.assertIsNotNone(chat)
                self.assertEqual(chat.find("llm-token-limit") is not None, flags[0])
                self.assertEqual(chat.find("llm-content-safety") is not None, flags[2])
                auth = list(policy.iter("authentication-managed-identity"))
                self.assertEqual(bool(auth), flags[3])
                for node in auth:
                    self.assertEqual(node.get("authentication-provider"), "WorkloadIdentity")
                    self.assertNotIn("client-id", node.attrib)
                for service_request in policy.iter("send-request"):
                    self.assertIsNotNone(service_request.find("authentication-managed-identity"))
                    self.assertFalse(any(node.get("name", "").lower() == "authorization"
                                         for node in service_request.findall("set-header")))
                variables = {node.get("name"): node.get("value") for node in policy.iter("set-variable")}
                self.assertEqual(variables["allowedModels"],
                                 ",".join(self.namespace["selected_models"]) if flags[1] else "")
                if flags[3]:
                    self.assertEqual(variables["continueOnNLPError"], "false")
                    self.assertIn('"selfHostedOriginalContent"', variables["selfHostedPiiMasked"])
                    self.assertIn("piiAnonymizedContent", variables["selfHostedPiiMasked"])
                self.assertIsNone(policy.find("./inbound/llm-token-limit"), "Bodyless discovery must bypass chat policies")
                self.assertEqual(self.namespace["parameters"]["apiNameMapping"], {"LLM": ["universal-llm-api"]})
                self.assertEqual(self.namespace["parameters"]["globalGatewayUrl"], "https://edge.example")
                self.assertFalse(self.namespace["parameters"]["useTargetAzureKeyVault"])
                self.assertTrue(self.namespace["artifact"].params_file.is_file())
                self.assertEqual({p.name for p in self.namespace["artifact"].params_file.parent.glob("*.xml")},
                                 {"self-hosted-policy.xml"})

    def test_default_plan_is_only_gpt_text_and_respects_explicit_filter(self):
        self.assertTrue(all(self.namespace[name] is True for name in SWITCHES))
        self.initialize()
        self.assertEqual(self.namespace["selected_models"], ["GPT-beta", "gpt-alpha"])
        self.namespace["model_allowlist"] = ["gpt-alpha"]
        self.initialize()
        self.assertEqual(self.namespace["selected_models"], ["gpt-alpha"])
        for names in ([], ["other-chat"], ["gpt-image-example"], ["unknown-gpt"], "gpt-alpha"):
            self.namespace["model_allowlist"] = names
            with self.subTest(names=names), self.assertRaises(ValueError):
                self.initialize()

    def test_empty_plan_and_invalid_feature_switch_fail_before_apim(self):
        self.context.catalog = ModelCatalog(self.context.config["llm_backends"], skipped_models=["gpt"])
        with self.assertRaisesRegex(ValueError, "No eligible"):
            self.initialize()
        self.namespace["APIMClientTool"].assert_not_called()
        self.namespace["enable_pii_processing"] = "false"
        with self.assertRaisesRegex(ValueError, "Feature switches"):
            self.initialize()

    def test_disabled_services_do_not_require_unused_prerequisites(self):
        self.namespace.update(enable_content_safety=False, enable_pii_processing=False,
                              content_safety_backend_id=None, content_safety_blocklist_id="unused")
        self.initialize()
        self.apim.client.backend.get.assert_not_called()
        self.apim.client.named_value.get.assert_not_called()

    def test_missing_edge_inputs_fail_by_name_without_managed_fallback(self):
        self.namespace.update(self_hosted_gateway_url=None, self_hosted_gateway_id=None)
        with self.assertRaises(ValueError) as raised:
            self.initialize()
        self.assertIn("self_hosted_gateway_url", str(raised.exception))
        self.assertIn("self_hosted_gateway_id", str(raised.exception))
        self.namespace["APIMClientTool"].assert_not_called()

    def test_azd_edge_defaults_are_used_without_overriding_explicit_values(self):
        self.namespace.update(self_hosted_gateway_url=None, self_hosted_gateway_id=None)
        self.context.azd_snapshot.update(VALIDATION_SELF_HOSTED_GATEWAY_URL="https://azd-edge.example",
                                         VALIDATION_SELF_HOSTED_GATEWAY_ID="azd-edge")
        with patch.dict(os.environ, {}, clear=True):
            self.initialize()
        self.assertEqual(self.namespace["models_api"], "https://azd-edge.example/models")
        self.namespace.update(self_hosted_gateway_url="https://override.example", self_hosted_gateway_id="override")
        self.initialize()
        self.assertEqual(self.namespace["models_api"], "https://override.example/models")

    def test_invalid_origins_managed_gateway_and_association_fail_before_deployment(self):
        for url in ("http://edge.example", "https://edge.example/models", "https://edge.example?key=value",
                    "https://user:secret@edge.example", "https://managed.example"):
            self.namespace["self_hosted_gateway_url"] = url
            with self.subTest(url=url), self.assertRaises(ValueError):
                self.initialize()
        self.namespace["self_hosted_gateway_url"] = "https://edge.example"
        self.namespace["self_hosted_gateway_id"] = "managed"
        with self.assertRaises(ValueError):
            self.initialize()
        self.namespace["self_hosted_gateway_id"] = "edge-fixture"
        self.apim.client.gateway_api.list_by_service.return_value = []
        with self.assertRaisesRegex(ValueError, "Associate"):
            self.initialize()

    def test_run_all_uses_edge_only_exact_key_and_opt_in_owned_cleanup(self):
        self.deploy()
        session = self.session()
        self.discover(session)
        session.post.return_value = self.chat_response()
        self.execute(5)
        session.post.return_value = response(403, {"error": {"code": "unauthorized_model_access"}})
        self.execute(6)
        self.execute(7)
        self.execute(8)
        self.assertEqual(session.headers["api-key"], "fixture-key-not-persisted")
        self.assertEqual(session.get.call_args.args[0], "https://edge.example/models/deployments")
        self.assertEqual([call.kwargs["json"]["model"] for call in session.post.call_args_list[:2]],
                         ["GPT-beta", "gpt-alpha"])
        for call in session.get.call_args_list + session.post.call_args_list:
            self.assertTrue(call.args[0].startswith("https://edge.example/models/"))
            self.assertIs(call.kwargs["allow_redirects"], False)
            self.assertNotIn("verify", call.kwargs)
        self.apim.get_subscription_key.assert_called_once_with("owned-subscription")
        self.apim.client.product.delete.assert_not_called()
        self.namespace["cleanup_enabled"] = True
        self.execute(8)
        self.apim.client.product.delete.assert_called_once_with(
            resource_group_name="fixture-rg", service_name="fixture-apim", product_id="owned-product",
            if_match="*", delete_subscriptions=True)
        for path in self.namespace["run_dir"].rglob("*"):
            if path.is_file():
                self.assertNotIn("fixture-key-not-persisted", path.read_text(encoding="utf-8"))

    def test_discovery_does_not_accept_missing_leaked_empty_or_id_only_entries(self):
        self.deploy()
        session = self.session()
        for body in ({"value": []}, {"value": [{"id": "gpt-alpha"}]},
                     {"value": [{"name": "gpt-alpha"}]},
                     {"value": [{"name": name} for name in ("GPT-beta", "gpt-alpha", "other-chat")]}):
            session.get.return_value = response(200, body)
            with self.subTest(body=body), self.assertRaises((RuntimeError, ValueError)):
                self.execute(4)

    def test_rbac_off_does_not_expand_the_chat_plan(self):
        self.namespace["enable_model_rbac"] = False
        self.deploy()
        session = self.session()
        self.discover(session, ["gpt-alpha", "GPT-beta", "gpt-image-example", "other-chat"])
        self.assertEqual(self.namespace["test_models"], ["GPT-beta", "gpt-alpha"])

    def test_all_features_off_runs_without_feature_headers_or_negative_requests(self):
        self.namespace.update({name: False for name in SWITCHES})
        self.deploy()
        session = self.session()
        self.discover(session)
        session.post.return_value = response(200, {"choices": [{"message": {"content": "4"}}]}, {
            "x-citadel-gateway-id": "edge-fixture", "x-citadel-contract-run": self.namespace["run_id"],
        })
        self.execute(5)
        self.execute(6)
        self.execute(7)
        self.assertEqual(session.post.call_count, 2)
        self.assertEqual(self.namespace["summary"]["FAIL"], 0)
        self.assertEqual(self.namespace["summary"]["SKIP"], 4)
        for call in session.post.call_args_list:
            self.assertNotIn(self.namespace["pii_fixture"], call.kwargs["json"]["messages"][0]["content"])

    def test_sync_retries_only_expected_transient_statuses_and_never_transport_errors(self):
        self.deploy()
        session = self.session()
        valid = response(200, {"value": [{"name": name} for name in self.namespace["selected_models"]]})
        session.get.side_effect = [response(401, {}), valid]
        with patch("time.sleep") as sleep:
            self.execute(4)
        sleep.assert_called_once()
        for failure in (response(302, {}), response(500, {})):
            session.get.side_effect = None
            session.get.return_value = failure
            with self.assertRaises(RuntimeError):
                self.execute(4)
        session.get.side_effect = requests.exceptions.SSLError("Untrusted CA")
        with self.assertRaises(requests.exceptions.SSLError):
            self.execute(4)
        session.get.side_effect = None
        session.get.return_value = response(401, {})
        with patch("time.monotonic", side_effect=[0, 1000]), self.assertRaises(RuntimeError):
            self.execute(4)

    def test_http_success_without_feature_evidence_cannot_pass(self):
        self.deploy()
        session = self.session()
        self.discover(session)
        session.post.side_effect = [
            self.chat_response(**{"x-citadel-gateway-id": "managed", "x-citadel-pii-masked": "false"}),
            self.chat_response(**{"x-citadel-contract-run": "old-run", "x-citadel-capacity-remaining": "-1",
                                  "x-citadel-safety-checked": "false"}),
        ]
        self.execute(5)
        with self.assertRaises(ValidationError):
            self.execute(7)
        failed = {result.case.split(":")[-1] for result in self.namespace["run"].results if result.status == "FAIL"}
        self.assertEqual(failed, {"edge-identity", "pii-masked", "contract-sync", "token-accounting",
                                 "content-safety-traversed"})

    def test_chat_failures_are_collected_without_skipping_other_models(self):
        self.deploy()
        session = self.session()
        self.discover(session)
        session.post.side_effect = [requests.Timeout("edge unreachable"), response(200, {"choices": []})]
        self.execute(5)
        self.assertEqual(session.post.call_count, 2)
        with self.assertRaises(ValidationError):
            self.execute(7)

    def test_denial_requires_feature_specific_error_not_generic_forbidden(self):
        self.namespace.update(content_safety_blocklist_id="benign-fixture", content_safety_probe_text="validation marker")
        self.deploy()
        session = self.session()
        self.discover(session)
        session.post.side_effect = [
            response(403, {"error": {"code": "generic_forbidden"}}),
            response(403, {"error": {"code": "unauthorized_model_access"}}),
        ]
        self.execute(6)
        failures = [result.case for result in self.namespace["run"].results if result.status == "FAIL"]
        self.assertEqual(failures, ["model-rbac-denial", "content-safety-blocklist-denial"])
        session.post.side_effect = [
            response(403, {"error": {"code": "unauthorized_model_access"}}),
            response(403, {"error": {"code": "ContentSafetyViolation", "message": "Text blocklist match"}}),
        ]
        self.execute(6)
        self.assertEqual([result.status for result in self.namespace["run"].results[-3:]], ["PASS", "PASS", "SKIP"])

    def test_deployed_policy_mismatch_prevents_secret_retrieval(self):
        self.preview()
        self.stack.enter_context(patch.object(contracttools, "deploy_contract", return_value={
            "products": {"value": [{"productId": "owned-product"}]},
            "subscriptions": {"value": [{"productId": "owned-product", "name": "owned-subscription"}]},
        }))
        self.apim.client.product_policy.get.return_value.value = "<policies><inbound/></policies>"
        with self.assertRaisesRegex(RuntimeError, "differs"):
            self.execute(3)
        self.apim.get_subscription_key.assert_not_called()


if __name__ == "__main__":
    unittest.main()
