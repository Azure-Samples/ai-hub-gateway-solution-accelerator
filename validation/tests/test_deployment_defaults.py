"""Execute provisioning initialization/generation with real azd context mechanics.

Only azd/account/APIM boundaries are mocked. No deployments, live HTTP requests,
resource deletion or manually edited default notebook configuration are needed.
"""

from contextlib import redirect_stdout
from copy import deepcopy
import base64
import io
import json
from pathlib import Path
import shutil
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))

import contracttools
import notebookdefaults
import validationtools


ALIASES = "citadel-model-aliases-tests"
AFFINITY = "citadel-session-affinity-tests"
IMAGES = "citadel-image-models-tests"
PROVIDERS = "llm-backend-onboarding-extended-providers-runner"


def code_cells(name):
    notebook = json.loads((ROOT / "validation" / (name + ".ipynb")).read_text(encoding="utf-8"))
    return ["".join(cell["source"]) for cell in notebook["cells"] if cell["cell_type"] == "code"]


def fixture_backends(external=False):
    backends = [{
        "backendId": "foundry-east", "backendType": "ai-foundry",
        "endpoint": "https://fixture.services.ai.azure.com",
        "authType": "managed-identity", "protocol": "openai-compat",
        "circuitBreaker": {"enabled": False},
        "supportedModels": [
            {"name": "gpt-main", "sessionAwareModel": False},
            {"name": "gpt-second"},
            {"name": "gpt-mini"},
            {"name": "Legacy-chat"},
            {"name": "gpt-disabled"},
            {"name": "text-vector"},
            {"name": "image-main", "operations": ["image-generation"]},
            {"name": "image-editable"},
            {"name": "legacy-image"},
        ],
    }, {
        "backendId": "foundry-west", "backendType": "ai-foundry",
        "endpoint": "https://fixture-west.services.ai.azure.com",
        "authType": "managed-identity", "protocol": "openai-compat",
        "supportedModels": [{"name": "gpt-main"}, {"name": "Legacy-chat"}],
    }, {
        "backendId": "native-flux", "backendType": "azure-flux",
        "endpoint": "https://fixture-flux.services.ai.azure.com",
        "authType": "managed-identity",
        "supportedModels": [{"name": "flux-image"}, {"name": "legacy-flux"}],
    }]
    if external:
        auth_types = {
            "aws-bedrock": "api-key-bearer", "aws-bedrock-mantle": "api-key-bearer",
            "gemini": "api-key-gemini", "gemini-openai": "api-key-bearer",
            "anthropic": "api-key-anthropic",
        }
        for backend_type, auth_type in auth_types.items():
            backends.append({
                "backendId": backend_type, "backendType": backend_type,
                "endpoint": f"https://{backend_type}.example",
                "authType": auth_type,
                "authConfig": {
                    "namedValueKey": backend_type + "-credential",
                    "keyVaultSecretUri": f"https://fixture.vault.azure.net/secrets/{backend_type}",
                },
                "supportedModels": [
                    {"name": backend_type + "-chat"},
                    {"name": backend_type + "-legacy"},
                    {"name": backend_type + "-image"},
                    {"name": backend_type + "-text-embedding"},
                ],
            })
    return backends


def snapshot(backends=None, external=False):
    return {
        "AZURE_ENV_NAME": "fixture-env", "AZURE_SUBSCRIPTION_ID": "fixture-subscription",
        "AZURE_RESOURCE_GROUP": "fixture-rg", "AZURE_LOCATION": "fixture-region",
        "APIM_NAME": "fixture-apim",
        "LLM_BACKEND_CONFIG": json.dumps(backends if backends is not None else fixture_backends(external)),
        "MODEL_ALIASES": json.dumps([
            {"name": "existing-legacy-alias", "models": ["Legacy-chat"], "strategy": "priority"},
        ]),
        "VALIDATION_SKIPPED_MODELS": '["LeGaCy", "MINI"]',
        "VALIDATION_MODEL_CAPABILITIES": '{"gpt-disabled": []}',
        "LLM_BACKEND_TEMPLATE_OPTIONS": json.dumps({
            "configureCircuitBreaker": False,
            "circuitBreakerDefaults": {"failureCount": 7},
            "sessionAffinityDefaults": {"cookieName": "existing-cookie", "source": "Cookie"},
            "anthropicVersion": "2023-06-01", "awsRegion": "fixture-region",
        }),
    }


class DeploymentDefaultsTests(unittest.TestCase):
    def setUp(self):
        self.directory = ROOT / "validation" / ".runs" / ("deployment-default-tests-" + uuid.uuid4().hex)
        self.directory.mkdir(parents=True)
        self.account = {"id": "fixture-subscription", "tenantId": "fixture-tenant"}
        self.apim = Mock()
        self.apim.apim_resource_name = "fixture-apim"
        self.apim.apim_resource_gateway_url = "https://gateway.example"
        self.apim.apim_service_id = "/subscriptions/fixture-subscription/resourceGroups/fixture-rg/providers/Microsoft.ApiManagement/service/fixture-apim"
        self.apim.discover_api_exact.side_effect = lambda path: {"url": "https://gateway.example/" + path}
        self.apim.client.product.list_by_service.return_value = []
        identity_id = (
            "/subscriptions/identity-subscription/resourceGroups/identity-rg/"
            "providers/Microsoft.ManagedIdentity/userAssignedIdentities/fixture-identity"
        )
        self.apim.client.api_management_service.get.return_value = SimpleNamespace(
            identity=SimpleNamespace(user_assigned_identities={identity_id: SimpleNamespace(client_id="fixture-client")})
        )
        self.output = io.StringIO()

    def tearDown(self):
        shutil.rmtree(self.directory)

    def execute(self, source, namespace):
        with redirect_stdout(self.output), \
                patch.object(contracttools, "deploy_contract", side_effect=AssertionError("No Azure deployments in tests")):
            exec(compile(source, "<deployment-notebook-cell>", "exec"), namespace)

    def initialize(self, name, values=None, settings=None):
        namespace = {}
        cells = code_cells(name)
        self.execute(cells[0], namespace)
        # Only run-owned output paths change; notebook user configuration stays untouched.
        namespace["run_dir"] = self.directory / name
        namespace["APIMClientTool"] = Mock(return_value=self.apim)
        namespace.update(settings or {})
        values = values if values is not None else snapshot(external=name == PROVIDERS)
        self.apim.get_backends.return_value = (
            [{"name": item["backendId"]} for item in json.loads(values["LLM_BACKEND_CONFIG"])], [],
        )
        with patch.object(validationtools, "_run_json", side_effect=[values, self.account]) as commands:
            self.execute(cells[1], namespace)
        self.assertEqual(commands.call_args_list[0].args[0][:3], ["azd", "env", "get-values"])
        self.assertEqual(commands.call_count, 2)
        # Initializers build the normal run path; subsequent writes stay in this test's directory.
        actual_run_dir = namespace["run_dir"]
        namespace["run_dir"] = self.directory / name
        if actual_run_dir.is_dir():
            actual_run_dir.rmdir()
        namespace["deploy_contract"] = Mock(side_effect=AssertionError("No Azure deployments in tests"))
        return namespace, cells

    def generate(self, name, values=None, settings=None):
        namespace, cells = self.initialize(name, values, settings)
        if name in (IMAGES, AFFINITY):
            self.execute(cells[2], namespace)  # API discovery and owned-product inventory.
            self.execute(cells[3], namespace)  # Real write_parameters + preview.
        elif name == ALIASES:
            self.execute(cells[2], namespace)  # Real prepare_artifact + preview.
        else:
            self.execute(cells[2], namespace)  # Visible alias definitions.
            self.execute(cells[3], namespace)  # Real prepare_artifact + preview.
        return namespace

    def assert_inventory_preserved(self, parameters, values):
        expected = json.loads(values["LLM_BACKEND_CONFIG"])
        self.assertEqual(
            [(item["backendId"], [model["name"] for model in item["supportedModels"]]) for item in parameters["llmBackendConfig"]],
            [(item["backendId"], [model["name"] for model in item["supportedModels"]]) for item in expected],
        )
        self.assertEqual(parameters["modelAliases"][0], json.loads(values["MODEL_ALIASES"])[0])
        self.assertFalse(parameters["configureCircuitBreaker"])
        self.assertEqual(parameters["circuitBreakerDefaults"], {"failureCount": 7})
        self.assertEqual(parameters["apimManagedIdentity"], {
            "subscriptionId": "identity-subscription", "resourceGroupName": "identity-rg", "name": "fixture-identity",
        })

    def test_all_four_default_initializers_generate_from_azd_mixed_models(self):
        for name in (ALIASES, AFFINITY, IMAGES, PROVIDERS):
            with self.subTest(notebook=name):
                values = snapshot(external=name == PROVIDERS)
                namespace = self.generate(name, values)
                params = namespace["onboarding_parameters"] if name in (IMAGES, AFFINITY) else namespace["backend_parameters"]
                self.assert_inventory_preserved(params, values)
                self.assertIsNone(namespace["source_parameters_file"])
                self.assertNotIn("supported_operation", self.output.getvalue())
                self.apim.client.api_management_service.get.assert_called()
                if name in (IMAGES, AFFINITY):
                    self.assertTrue(namespace["run_backend_onboarding"])
                    text = namespace["onboarding_params"].read_text(encoding="utf-8")
                else:
                    self.assertTrue(namespace["approve_shared_routing"])
                    text = namespace["backend_artifact"].params_file.read_text(encoding="utf-8")
                for retained in ("Legacy-chat", "text-vector", "image-main", "existing-legacy-alias"):
                    self.assertIn(retained, text)
                self.assertIn("using ", text)

    def test_alias_members_and_native_provider_loops_do_not_select_exclusions(self):
        aliases = self.generate(ALIASES)
        for alias in aliases["model_aliases"]:
            self.assertEqual(alias["models"], ["gpt-main", "gpt-second"])
        providers = self.generate(PROVIDERS)
        for backend_type, models in providers["provider_models"].items():
            for model in models:
                self.assertFalse(any(word in model.casefold() for word in ("legacy", "mini", "image", "text", "disabled")))
        self.assertEqual(providers["provider_models"]["anthropic"], ["anthropic-chat"])
        posted = []

        def request(method, url, **kwargs):
            posted.append((url, kwargs["json"]))
            return SimpleNamespace(headers={}, json_body={}, error=None, status_code=200, duration=0)

        providers["transport"] = SimpleNamespace(request=request)
        providers["unified_api"] = {"url": "https://gateway.example/unified-ai"}
        providers["models_api"] = {"url": "https://gateway.example/models"}
        providers["headers"] = {"api-key": "fixture"}
        providers["record"] = lambda case, result, **kwargs: result
        for text in code_cells(PROVIDERS):
            if any(marker in text for marker in (
                "messages = [", 'for model in provider_models.get("aws-bedrock"',
                'for model in provider_models.get("gemini"', 'for model in provider_models.get("anthropic"',
            )):
                self.execute(text, providers)
        self.assertGreater(len(posted), 0)
        self.assertTrue(any("/bedrock/" in url for url, _ in posted))
        # Case-insensitive substring matching means "MINI" also excludes "geMINI".
        self.assertEqual(providers["provider_models"]["gemini"], [])
        self.assertFalse(any("/gemini/" in url for url, _ in posted))
        self.assertTrue(any("/claude/" in url for url, _ in posted))
        self.assertFalse(any("legacy" in str(item).lower() or "mini" in str(item).lower() for item in posted))

    def test_affinity_flags_only_selected_models_and_keeps_inventory(self):
        values = snapshot()
        namespace = self.generate(AFFINITY, values)
        before = json.loads(values["LLM_BACKEND_CONFIG"])
        after = namespace["onboarding_parameters"]["llmBackendConfig"]
        for old, new in zip(before, after):
            for old_model, new_model in zip(old["supportedModels"], new["supportedModels"]):
                expected = dict(old_model)
                if expected["name"] == namespace["target_model"] and old["backendId"] in namespace["selected_members"]:
                    expected["sessionAwareModel"] = True
                self.assertEqual(new_model, expected)
        self.assertEqual(namespace["target_model"], "gpt-main")
        self.assertTrue(namespace["onboarding_parameters"]["configureSessionAffinity"])

    def test_image_missing_edit_and_negative_prerequisites_skip_but_generation_remains(self):
        backends = fixture_backends()[:1]
        backends[0]["supportedModels"] = [
            {"name": "image-main", "operations": ["image-generation"]},
            {"name": "legacy-image"}, {"name": "text-vector"}, {"name": "gpt-main"},
        ]
        namespace = self.generate(IMAGES, snapshot(backends))
        self.assertTrue(namespace["image_ready"])
        self.assertEqual(namespace["allowed_models_list"], ["image-main"])
        self.assertIsNone(namespace["edit_header_model"])
        self.assertIsNone(namespace["disallowed_image_model"])
        self.assertTrue(all(item.status == "SKIP" for item in namespace["run"].results))

    def test_image_native_provider_selection_honors_skips_and_operations(self):
        namespace = self.generate(IMAGES)
        self.assertEqual(namespace["openai_image_model"], "image-main")
        self.assertEqual(namespace["flux_image_model"], "flux-image")
        self.assertIsNone(namespace["mai_image_model"])
        for field in ("openai_image_model", "flux_image_model", "edit_header_model", "disallowed_image_model"):
            model = namespace[field]
            self.assertFalse(model and namespace["context"].catalog.is_skipped(model))
        self.assertIn("image-generation", namespace["context"].catalog.operations("image-main"))

    def test_real_image_generation_loops_send_only_eligible_models(self):
        from PIL import Image
        import requests

        namespace = self.generate(IMAGES)
        image = io.BytesIO()
        Image.new("RGB", (2, 2), "red").save(image, format="PNG")
        response = requests.Response()
        response.status_code = 200
        response.headers["Content-Type"] = "application/json"
        response._content = json.dumps({
            "data": [{"b64_json": base64.b64encode(image.getvalue()).decode()}],
        }).encode()
        post = Mock(return_value=response)
        namespace.update({
            "requests": SimpleNamespace(post=post),
            "images_generations_url": "https://gateway.example/unified-ai/v1/images/generations",
            "deployments_generations_url": lambda model: "https://gateway.example/unified-ai/openai/deployments/" + model + "/images/generations",
            "api_key": "fixture",
        })
        cells = code_cells(IMAGES)
        self.execute(next(text for text in cells if "def decoded_image" in text), namespace)
        for model in ("openai_image_model", "flux_image_model", "mai_image_model"):
            self.execute(next(text for text in cells if "generate_image(" + model in text), namespace)
        self.assertEqual([call.kwargs["json"]["model"] for call in post.call_args_list],
                         ["image-main", "image-main", "flux-image"])
        self.assertTrue(all(item.status != "FAIL" for item in namespace["run"].results))
        with self.assertRaisesRegex(ValueError, "non-skipped"):
            namespace["generate_image"]("legacy-image", "This must never be sent.")
        self.assertEqual(post.call_count, 3)

    def test_explicit_operation_and_keyword_overrides_filter_rebuilt_catalogs(self):
        namespace = self.generate(IMAGES, settings={
            "operation_overrides": {"image-main": [], "flux-image": []},
            "skipped_models": ["EDITABLE", "LEGACY", "MINI"],
        })
        self.assertFalse(namespace["image_ready"])
        self.assertEqual(namespace["context"].catalog.operations("image-main"), [])
        self.assertEqual(len(namespace["source_parameters"]["llmBackendConfig"]), 3)
        providers = self.generate(PROVIDERS, settings={
            "operation_overrides": {"anthropic-chat": [], "gemini-chat": []},
        })
        self.assertEqual(providers["provider_models"]["anthropic"], [])
        self.assertEqual(providers["provider_models"]["gemini"], [])

    def test_optional_scenarios_report_skip_not_empty_success_or_cloud_calls(self):
        values = snapshot([{
            "backendId": "embed-only", "backendType": "ai-foundry",
            "endpoint": "https://fixture.services.ai.azure.com", "supportedModels": [{"name": "text-vector"}],
        }])
        for name in (ALIASES, AFFINITY, IMAGES):
            with self.subTest(notebook=name):
                namespace, cells = self.initialize(name, values)
                for text in cells[2:]:
                    self.execute(text, namespace)
                self.assertTrue(namespace["run"].results)
                self.assertEqual({item.status for item in namespace["run"].results}, {"SKIP"})
                namespace["deploy_contract"].assert_not_called()
        self.assertIn("no tests executed", self.output.getvalue().lower())

    def test_explicit_source_file_is_authoritative_and_retains_global_settings(self):
        source = {
            "llmBackendConfig": deepcopy(fixture_backends()),
            "modelAliases": [{"name": "source-only", "models": ["gpt-main"], "strategy": "priority"}],
            "configureCircuitBreaker": True, "awsRegion": "source-region",
            "apimManagedIdentity": {"subscriptionId": "source-sub", "resourceGroupName": "source-rg", "name": "source-identity"},
        }
        source["llmBackendConfig"][0]["supportedModels"].insert(0, {"name": "gpt-source-only"})
        source_path = self.directory / "source.json"
        source_path.write_text(json.dumps(source), encoding="utf-8")
        for name in (ALIASES, AFFINITY, IMAGES, PROVIDERS):
            with self.subTest(notebook=name):
                # Provider source also includes genuinely external endpoints and independent references.
                effective = deepcopy(source)
                if name == PROVIDERS:
                    effective["llmBackendConfig"] += fixture_backends(external=True)[3:]
                source_path.write_text(json.dumps(effective), encoding="utf-8")
                namespace = self.generate(name, settings={"source_parameters_file": source_path})
                self.assertIn("gpt-source-only", [entry.name for entry in namespace["context"].catalog.entries])
                params = namespace.get("onboarding_parameters", namespace.get("backend_parameters"))
                self.assertEqual(params["modelAliases"][0]["name"], "source-only")
                self.assertTrue(params["configureCircuitBreaker"])
                self.assertEqual(params["awsRegion"], "source-region")
                self.assertEqual(params["apimManagedIdentity"]["name"], "source-identity")
        self.assertEqual(json.loads(source_path.read_text(encoding="utf-8")), effective)

    def test_external_provider_absence_remains_actionable_not_source_approval_requirement(self):
        with self.assertRaisesRegex(ValueError, "external.*backend_endpoint_and_credentials"):
            self.initialize(PROVIDERS, snapshot())

    def test_sdk_identity_ambiguity_requires_explicit_coordinates(self):
        self.apim.client.api_management_service.get.return_value.identity.user_assigned_identities = {
            "first": {}, "second": {},
        }
        with self.assertRaisesRegex(ValueError, "one user-assigned identity"):
            self.initialize(ALIASES)

    def test_direct_azd_global_keys_are_optional_and_preserved(self):
        values = snapshot()
        values.pop("LLM_BACKEND_TEMPLATE_OPTIONS")
        values["CONFIGURE_CIRCUIT_BREAKER"] = "false"
        values["CIRCUIT_BREAKER_DEFAULTS"] = '{"failureCount": 8}'
        values["AWS_REGION"] = "direct-region"
        namespace = self.generate(ALIASES, values)
        self.assertFalse(namespace["backend_parameters"]["configureCircuitBreaker"])
        self.assertEqual(namespace["backend_parameters"]["circuitBreakerDefaults"], {"failureCount": 8})
        self.assertEqual(namespace["backend_parameters"]["awsRegion"], "direct-region")


if __name__ == "__main__":
    unittest.main()
