"""Execute every onboarding cell with real helpers and mocked cloud boundaries."""
import io
import importlib
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))
import apimtools
import validationtools
import requests
from openai import OpenAI

SDK_HTTP = importlib.import_module(OpenAI.__init__.__module__).httpx2


class DefaultOnboardingRunAllTests(unittest.TestCase):
    def test_notebook_contains_no_legacy_test_routes_or_client(self):
        notebook = json.loads(
            (ROOT / "validation" / "llm-backend-onboarding-runner.ipynb").read_text(encoding="utf-8")
        )
        source = "\n".join("".join(cell["source"]) for cell in notebook["cells"]
                           if cell["cell_type"] == "code")
        for legacy in ('AzureOpenAI', 'discover_api_exact("openai")', '"/deployments/',
                       "/openai/", "azure-openai-api", "unified-ai-api", "api-version",
                       "/responses/", "input_items", "optional_response_retrieval"):
            with self.subTest(legacy=legacy):
                self.assertNotIn(legacy, source)

    def run_notebook(self, settings=None, notebook_name="llm-backend-onboarding-runner.ipynb",
                     retrieval_status=None, create_status=200, non_json_retrieval=False):
        names = ["gpt-main", "gpt-mini", "text-vector", "flux-image", "my-legacy-chat"]
        backend = {
            "backendId": "fixture-backend", "backendType": "ai-foundry",
            "endpoint": "https://fixture.services.ai.azure.com", "authType": "managed-identity",
            "supportedModels": [{"name": name, "modelFormat": "OpenAI"} for name in names],
        }
        backend["supportedModels"][0]["apiVersion"] = "2025-04-01-preview"
        snapshot = {
            "AZURE_ENV_NAME": "fixture-env", "AZURE_SUBSCRIPTION_ID": "fixture-sub",
            "AZURE_TENANT_ID": "fixture-tenant", "AZURE_RESOURCE_GROUP": "fixture-rg",
            "AZURE_LOCATION": "fixture-region", "APIM_NAME": "fixture-apim",
            "LLM_BACKEND_CONFIG": json.dumps([backend]),
        }
        account = {"id": "fixture-sub", "tenantId": "fixture-tenant",
                   "name": "Fixture Subscription", "user": {"name": "fixture-user"}}
        namespace = {}
        posted_models = []
        request_methods = []
        requested_urls = []
        sdk_requests = []

        def assert_universal(url):
            self.assertTrue(str(url).startswith("https://gateway.example/models/"), str(url))
            self.assertNotIn("/openai/", str(url))
            self.assertNotIn("/deployments/", str(url))
            self.assertNotIn("api-version", str(url))
            requested_urls.append(str(url))

        def response(url, body, status=200):
            result = requests.Response()
            result.status_code = status
            result.url = url
            result.headers["Content-Type"] = "application/json"
            result._content = json.dumps(body).encode()
            return result

        def get(url, **kwargs):
            request_methods.append(("GET", str(url)))
            assert_universal(url)
            if "/responses/" in url:
                if notebook_name == "llm-backend-onboarding-runner.ipynb":
                    raise AssertionError("Onboarding must not retrieve Responses or input-items")
                if retrieval_status is not None and retrieval_status != 200:
                    result = response(url, {"error": {"code": "retrieval-error"}}, retrieval_status)
                    if non_json_retrieval:
                        result._content = b"Response object not available"
                        result.headers["Content-Type"] = "text/plain"
                    return result
                if "resp-gpt-mini" in url:
                    return response(url, {"error": {"code": "OperationNotSupported"}}, 404)
                if url.endswith("/input_items"):
                    return response(url, {"data": [{"type": "message"}]})
                return response(url, {"id": url.rsplit("/", 1)[-1], "status": "completed"})
            entries = [{"name": name, "id": name, "type": "ai-foundry"} for name in names]
            return response(url, {"value": entries} if url.endswith("/deployments") else {"data": entries})

        def post(url, **kwargs):
            request_methods.append(("POST", str(url)))
            assert_universal(url)
            self.assertNotIn("api-version", kwargs.get("params", {}))
            body = kwargs["json"]
            model = body.get("model")
            self.assertIsNotNone(model, "Universal LLM requires the model in the body")
            posted_models.append(model)
            if model == "definitely-not-a-real-model-xyz":
                return response(url, {"error": {"code": "model_not_found"}}, 404)
            if url.endswith("/embeddings"):
                return response(url, {"data": [{"embedding": [0.1, 0.2]}]})
            if url.endswith("/responses"):
                if create_status != 200:
                    return response(url, {"error": {"code": "create-error"}}, create_status)
                return response(url, {"id": "resp-" + model, "output": [
                    {"content": [{"type": "output_text", "text": "Four"}]}]})
            result = response(url, {"choices": [{"message": {"content": "Four"}}]})
            for alias in namespace.get("model_aliases") or []:
                if model == alias["name"]:
                    result.headers["UAIG-Alias"] = model
                    result.headers["UAIG-Resolved-Model"] = alias["models"][0]
            return result

        apim = Mock()
        apim.apim_resource_name = "fixture-apim"
        apim.apim_resource_gateway_url = "https://gateway.example"
        apim.get_managed_identity_info.return_value = {"name": "fixture-mi", "resourceGroup": "fixture-rg"}
        apim.get_subscription_key.return_value = "fixture-not-a-live-key"
        def discover(path):
            self.assertEqual(path, "models", "Only Universal LLM may be discovered")
            return {"id": path, "name": path, "path": path, "url": "https://gateway.example/" + path}
        apim.discover_api_exact.side_effect = discover
        apim.client.backend.list_by_service.return_value = [SimpleNamespace(name="fixture-backend")]
        apim.client.policy_fragment.get.return_value.value = "<fragment/>"

        session = MagicMock()
        session.__enter__.return_value = session
        session.headers = {}
        session.post.side_effect = post
        session.get.side_effect = get
        def sdk_handler(request):
            assert_universal(request.url)
            self.assertEqual(request.url.path, "/models/chat/completions")
            self.assertEqual(request.headers["api-key"], "fixture-not-a-live-key")
            body = json.loads(request.content)
            self.assertIn("model", body)
            sdk_requests.append({"url": str(request.url), "body": body})
            chunk = {"id": "sdk-chat", "object": "chat.completion.chunk", "created": 0,
                     "model": body["model"],
                     "choices": [{"index": 0, "delta": {"content": "Four"}, "finish_reason": "stop"}]}
            if body.get("stream"):
                return SDK_HTTP.Response(200, headers={"Content-Type": "text/event-stream"},
                    content=("data: " + json.dumps(chunk) + "\n\ndata: [DONE]\n\n").encode())
            return SDK_HTTP.Response(200, json={
                "id": "sdk-chat", "object": "chat.completion", "created": 0, "model": body["model"],
                "choices": [{"index": 0, "message": {"role": "assistant", "content": "Four"},
                             "finish_reason": "stop"}],
            })

        def sdk_factory(**kwargs):
            self.assertEqual(kwargs["base_url"], "https://gateway.example/models/")
            self.assertNotIn("api_version", kwargs)
            self.assertEqual(kwargs["max_retries"], 0)
            return OpenAI(**kwargs, http_client=SDK_HTTP.Client(transport=SDK_HTTP.MockTransport(sdk_handler)))
        deployed = []

        def deploy(params_file, location, name):
            deployed.append((params_file.name, location, name, params_file.read_text(encoding="utf-8")))
            if params_file.parent.name == "backends":
                return {"backendIds": {"type": "array", "value": ["fixture-backend"]}}
            return {"endpoints": {"type": "array", "value": [{
                "productId": namespace["product_id"],
                "subscriptionName": namespace["product_id"] + "-SUB-01",
            }]}}

        code_cells = [
            "".join(cell["source"]) for cell in json.loads(
                (ROOT / "validation" / notebook_name).read_text(encoding="utf-8")
            )["cells"] if cell["cell_type"] == "code"
        ]
        error = None
        log = io.StringIO()
        with tempfile.TemporaryDirectory() as temporary, redirect_stdout(log), \
                patch.object(validationtools, "_run_json", side_effect=[snapshot, account]), \
                patch.object(apimtools, "APIMClientTool", return_value=apim), \
                patch("requests.get", side_effect=get), patch("requests.post", side_effect=post), \
                patch("requests.Session", return_value=session), \
                patch("openai.OpenAI", side_effect=sdk_factory), \
                patch("openai.AzureOpenAI", side_effect=AssertionError("Legacy client is not allowed")):
            for index, source in enumerate(code_cells):
                if index == 1:
                    with patch.object(Path, "mkdir"):
                        exec(compile(source, f"onboarding:{index}", "exec"), namespace)
                    namespace["_initialization_log"] = log.getvalue()
                    namespace["run_dir"] = Path(temporary)
                else:
                    if index == 2:
                        namespace["deploy_contract"] = deploy
                    try:
                        exec(compile(source, f"onboarding:{index}", "exec"), namespace)
                    except validationtools.ValidationError as caught:
                        error = caught
                        break
                if index == 0 and settings:
                    namespace.update(settings)
        namespace["_requested_urls"] = requested_urls
        namespace["_request_methods"] = request_methods
        namespace["_sdk_requests"] = sdk_requests
        return namespace, deployed, posted_models, log.getvalue(), error

    def test_run_all_with_standard_azd_outputs_and_unchanged_configuration(self):
        namespace, deployed, posted, log, error = self.run_notebook()
        self.assertIsNone(error, log[-2000:])
        self.assertEqual(len(deployed), 2)
        self.assertNotIn("complete_backend_configuration", namespace)
        self.assertNotIn("approve_shared_routing", namespace)
        self.assertEqual(namespace["context"].config["capabilities"], {})
        self.assertNotIn("api_version", namespace)
        self.assertEqual(len(namespace["_sdk_requests"]), 2)
        self.assertFalse(namespace["_sdk_requests"][0]["body"].get("stream", False))
        self.assertIs(namespace["_sdk_requests"][1]["body"]["stream"], True)
        self.assertTrue(any(r.case == "universal-sdk" and r.status == "PASS" for r in namespace["run"].results))
        self.assertTrue(any(r.case == "universal-sdk-streaming" and r.status == "PASS"
                            for r in namespace["run"].results))
        self.assertIn("'universal-llm-api'", deployed[1][3])
        self.assertNotIn("azure-openai-api", deployed[1][3])
        self.assertNotIn("unified-ai-api", deployed[1][3])
        self.assertIn("gpt-main", posted)
        self.assertIn("gpt-mini", posted)
        self.assertIn("text-vector", posted)
        self.assertNotIn("flux-image", posted)
        for value in ("fixture-sub", "fixture-tenant", "fixture-rg", "fixture-apim", "Fixture Subscription"):
            self.assertIn(value, namespace["_initialization_log"])
        self.assertIn("inferred", namespace["_initialization_log"])
        mini = [result for result in namespace["run"].results if "gpt-mini:responses:" in result.case]
        self.assertEqual([result.status for result in mini], ["PASS"])
        self.assertFalse(any("/responses/" in url for url in namespace["_requested_urls"]))
        response_calls = [(method, url) for method, url in namespace["_request_methods"] if "/responses" in url]
        self.assertTrue(response_calls)
        self.assertTrue(all(method == "POST" for method, _ in response_calls))
        self.assertFalse(any(result.status == "FAIL" for result in namespace["run"].results))

    def test_skip_keywords_exclude_requests_but_preserve_deployed_models(self):
        namespace, deployed, posted, _, error = self.run_notebook({"skipped_models": ["MINI", "legacy"]})
        self.assertIsNone(error)
        self.assertNotIn("gpt-mini", posted)
        self.assertNotIn("my-legacy-chat", posted)
        self.assertIn("gpt-mini", deployed[0][3])
        self.assertIn("my-legacy-chat", deployed[0][3])
        skipped = [r.case for r in namespace["run"].results if r.status == "SKIP"]
        self.assertIn("model:gpt-mini", skipped)
        self.assertIn("model:my-legacy-chat", skipped)

    def test_explicit_mini_override_still_only_creates_responses_in_onboarding(self):
        namespace, _, _, _, error = self.run_notebook({"operation_overrides": {
            "gpt-mini": ["chat", "responses"],
        }})
        self.assertIsNone(error)
        cases = [r.case for r in namespace["run"].results if "gpt-mini:responses:" in r.case]
        self.assertEqual(cases, ["gpt-mini:responses:create"])
        self.assertFalse(any("/responses/" in url for url in namespace["_requested_urls"]))

    def test_alias_with_excluded_member_is_not_invoked(self):
        namespace, _, posted, _, error = self.run_notebook({
            "skipped_models": ["mini"],
            "model_aliases": [{"name": "my-alias", "models": ["gpt-main", "gpt-mini"], "strategy": "priority"}],
        })
        self.assertIsNone(error)
        self.assertNotIn("my-alias", posted)
        self.assertTrue(any(r.case == "alias:my-alias" and r.status == "SKIP"
                            for r in namespace["run"].results))

    def test_explicit_chat_only_override_does_not_run_sdk_streaming(self):
        namespace, _, _, _, error = self.run_notebook({
            "operation_overrides": {"gpt-mini": ["chat"]}, "model_override": "gpt-mini",
        })
        self.assertIsNone(error)
        self.assertTrue(any(r.case == "universal-sdk-streaming" and r.status == "SKIP"
                            for r in namespace["run"].results))
        self.assertFalse(any("gpt-mini:responses" in r.case for r in namespace["run"].results))

    def test_alias_requests_use_only_universal_llm(self):
        namespace, _, posted, _, error = self.run_notebook({
            "model_aliases": [{"name": "my-alias", "models": ["gpt-main"], "strategy": "priority"}],
        })
        self.assertIsNone(error)
        self.assertIn("my-alias", posted)
        results = [r for r in namespace["run"].results if r.case.startswith("alias:my-alias:")]
        self.assertEqual([(r.case, r.status) for r in results], [("alias:my-alias:models", "PASS")])

    def test_no_chat_models_skip_sdk_without_discovering_a_legacy_api(self):
        namespace, _, posted, _, error = self.run_notebook({
            "skipped_models": ["gpt", "legacy"],
        })
        self.assertIsNone(error)
        self.assertEqual(namespace["_sdk_requests"], [])
        self.assertIn("text-vector", posted)
        self.assertTrue(any(r.case == "universal-sdk" and r.status == "SKIP"
                            for r in namespace["run"].results))

    def test_all_models_default_run_accepts_mixed_inventory_without_customization(self):
        namespace, deployed, posted, _, error = self.run_notebook(
            notebook_name="citadel-universal-llm-api-all-models-tests.ipynb")
        self.assertIsNone(error)
        self.assertEqual(len(deployed), 1)
        self.assertEqual(namespace["context"].config["capabilities"], {})
        self.assertIn("text-vector", posted)
        self.assertNotIn("flux-image", posted)
        self.assertTrue(any(r.case == "operations:flux-image" and r.status == "SKIP"
                            for r in namespace["run"].results))
        self.assertTrue(any("/responses/" in url for url in namespace["_requested_urls"]))

    def test_all_models_skips_are_applied_before_operation_planning(self):
        namespace, _, posted, _, error = self.run_notebook(
            {"skipped_models": ["MINI", "legacy", "flux"]},
            notebook_name="citadel-universal-llm-api-all-models-tests.ipynb")
        self.assertIsNone(error)
        self.assertNotIn("gpt-mini", posted)
        self.assertNotIn("my-legacy-chat", posted)
        self.assertTrue(any(r.case == "model:flux-image" and r.status == "SKIP"
                            for r in namespace["run"].results))

    def test_all_models_get_404_is_warning_for_full_size_and_explicitly_mapped_models(self):
        for settings in (None, {"operation_overrides": {
            "gpt-main": ["chat", "responses"], "gpt-mini": ["chat", "responses"],
        }}):
            with self.subTest(settings=settings):
                namespace, _, _, log, error = self.run_notebook(
                    settings, notebook_name="citadel-universal-llm-api-all-models-tests.ipynb",
                    retrieval_status=404, non_json_retrieval=True)
                self.assertIsNone(error)
                results = [r for r in namespace["run"].results
                           if r.case.endswith((":get", ":input-items"))]
                self.assertEqual(len(results), 4)
                self.assertTrue(all(result.status == "SKIP" for result in results))
                self.assertTrue(all("404" in result.reason for result in results))
                self.assertIn("RESULT | WARNING", log)
                self.assertFalse(any(result.status == "FAIL" for result in namespace["run"].results))

    def test_all_models_non_404_get_errors_remain_failures(self):
        for status in (401, 403, 429, 500):
            with self.subTest(status=status):
                namespace, _, _, _, error = self.run_notebook(
                    notebook_name="citadel-universal-llm-api-all-models-tests.ipynb",
                    retrieval_status=status)
                self.assertIsInstance(error, validationtools.ValidationError)
                failed = [r for r in namespace["run"].results if r.status == "FAIL"]
                self.assertTrue(any(result.case == "gpt-main:responses:get" for result in failed))
                self.assertTrue(any(result.case == "gpt-main:responses:input-items" for result in failed))

    def test_responses_post_404_remains_a_failure(self):
        namespace, _, _, _, error = self.run_notebook(
            notebook_name="citadel-universal-llm-api-all-models-tests.ipynb", create_status=404)
        self.assertIsInstance(error, validationtools.ValidationError)
        self.assertTrue(any(result.case == "gpt-main:responses" and result.status == "FAIL"
                            for result in namespace["run"].results))


if __name__ == "__main__":
    unittest.main()
