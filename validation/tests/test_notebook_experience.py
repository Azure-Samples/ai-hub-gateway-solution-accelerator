"""Run the actual notebook cells offline to enforce the Run All experience."""
import ast
import base64
import contextlib
import io
import json
import os
import sys
import time
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))
import apimtools
import utils
import validationtools

NOTEBOOKS = sorted((ROOT / "validation").glob("*.ipynb"))
SCENARIOS = [path for path in NOTEBOOKS if "environment-setup" not in path.name]


def cells(name):
    notebook = json.loads((ROOT / "validation" / name).read_text(encoding="utf-8"))
    return ["".join(cell["source"]) for cell in notebook["cells"] if cell["cell_type"] == "code"]


def context_fixture(capabilities=None, backends=None):
    capabilities = capabilities if capabilities is not None else {
        "future-model": ["chat", "responses", "streaming", "image-generation", "image-edit"],
    }
    backends = backends if backends is not None else [{
        "backendId": "fixture", "backendType": "ai-foundry", "protocol": "openai-compat",
        "supportedModels": [{"name": "future-model", "modelFormat": "OpenAI"}],
    }]
    return SimpleNamespace(
        config={
            "subscription_id": "fixture-subscription", "resource_group": "fixture-rg",
            "location": "fixture-location", "apim_name": "fixture-apim",
            "llm_backends": backends, "capabilities": capabilities,
        },
        account={"tenantId": "fixture-tenant", "id": "fixture-subscription"},
        catalog=validationtools.ModelCatalog(backends, capabilities),
        azd_snapshot={},
    )


def configured(name):
    namespace = {}
    with contextlib.redirect_stdout(io.StringIO()), patch.object(Path, "mkdir"):
        exec(compile(cells(name)[0], name + ":configure", "exec"), namespace)
    return namespace


def initialize(name, namespace, context=None, apim=None):
    context = context if context is not None else context_fixture()
    boundary = apim if apim is not None else Mock(side_effect=AssertionError("Unexpected APIM boundary"))
    namespace["APIMClientTool"] = boundary
    with patch.object(validationtools.ValidationContext, "load", return_value=context), \
            patch.object(apimtools, "APIMClientTool", boundary), patch.object(Path, "mkdir"), \
            contextlib.redirect_stdout(io.StringIO()):
        exec(compile(cells(name)[1], name + ":initialize", "exec"), namespace)
    return boundary


def initialized_apim():
    boundary = Mock()
    apim = boundary.return_value
    apim.resource_group_name = "fixture-rg"
    apim.apim_resource_name = "fixture-apim"
    apim.apim_resource_gateway_url = "https://gateway.example"
    apim.apim_service_id = "/fixture/apim"
    apim.get_managed_identity_info.return_value = {
        "name": "fixture-identity", "resourceGroup": "fixture-rg", "clientId": "fixture-client",
    }
    apim.discover_api_exact.side_effect = lambda path: {
        "url": f"https://gateway.example/{path}", "path": path, "id": path, "name": path,
    }
    apim.client.product.list_by_service.return_value = []
    apim.client.backend.list_by_service.return_value = []
    apim.get_backends.return_value = ([], [])
    apim.client.api_management_service.get.return_value = SimpleNamespace(
        identity=SimpleNamespace(user_assigned_identities={
            "/subscriptions/fixture-subscription/resourceGroups/fixture-rg/providers/"
            "Microsoft.ManagedIdentity/userAssignedIdentities/fixture-identity":
            SimpleNamespace(client_id="fixture-client"),
        })
    )
    return boundary


def no_role_fixture(roles=None, expired=False):
    claims = {"aud": "api://fixture-client", "exp": time.time() + (-60 if expired else 600)}
    if roles:
        claims["roles"] = roles
    encoded = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
    return "fixture." + encoded + ".fixture-signature"


class NotebookExperienceStructureTests(unittest.TestCase):
    def test_all_fifteen_notebooks_have_guides_steps_and_no_saved_results(self):
        self.assertEqual(len(NOTEBOOKS), 15)
        for path in NOTEBOOKS:
            notebook = json.loads(path.read_text(encoding="utf-8"))
            code_index = 0
            for index, cell in enumerate(notebook["cells"]):
                if cell["cell_type"] != "code":
                    continue
                with self.subTest(notebook=path.name, cell=index):
                    guide = "".join(notebook["cells"][index - 1]["source"])
                    self.assertEqual(notebook["cells"][index - 1]["cell_type"], "markdown")
                    self.assertIn("**Input:**", guide)
                    self.assertIn("**Output:**", guide)
                    tree = ast.parse("".join(cell["source"]))
                    wrappers = [node for node in tree.body if isinstance(node, ast.With)]
                    self.assertEqual(len(wrappers), 1)
                    call = wrappers[0].items[0].context_expr
                    self.assertEqual(ast.unparse(call.func), "utils.notebook_step")
                    self.assertIn("namespace", [keyword.arg for keyword in call.keywords])
                    if code_index:
                        self.assertEqual(len(tree.body), 1, "All later executable statements belong to the step.")
                    self.assertEqual(cell["outputs"], [])
                    self.assertIsNone(cell["execution_count"])
                code_index += 1

    def test_scenarios_never_prompt_for_secrets_or_input(self):
        for path in SCENARIOS:
            for text in cells(path.name):
                tree = ast.parse(text)
                calls = {ast.unparse(node.func) for node in ast.walk(tree) if isinstance(node, ast.Call)}
                with self.subTest(notebook=path.name):
                    self.assertNotIn("getpass", calls)
                    self.assertNotIn("input", calls)
                    self.assertNotIn("getpass.getpass", calls)

    def test_configure_cells_do_not_initialize_or_deploy(self):
        for path in SCENARIOS:
            with self.subTest(notebook=path.name), patch.object(validationtools.ValidationContext, "load") as load, \
                    patch.object(apimtools, "APIMClientTool") as apim:
                configured(path.name)
                load.assert_not_called()
                apim.assert_not_called()

    def test_raw_requests_use_the_observable_native_response_adapter(self):
        for path in SCENARIOS:
            for text in cells(path.name):
                tree = ast.parse(text)
                raw_calls = [
                    ast.unparse(node.func) for node in ast.walk(tree)
                    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                    and isinstance(node.func.value, ast.Name) and node.func.value.id == "requests"
                    and node.func.attr in ("get", "post", "put", "patch", "delete")
                ]
                with self.subTest(notebook=path.name):
                    self.assertEqual(raw_calls, [])

    def test_deployment_approvals_and_required_onboarding_default_to_allowed(self):
        approval_inputs = {
            "approve_shared_routing", "source_configuration_complete", "backend_configuration_complete",
            "run_backend_onboarding",
        }
        for path in SCENARIOS:
            tree = ast.parse(cells(path.name)[0])
            for node in ast.walk(tree):
                if not isinstance(node, ast.Assign):
                    continue
                for target in node.targets:
                    if isinstance(target, ast.Name) and target.id in approval_inputs:
                        with self.subTest(notebook=path.name, parameter=target.id):
                            self.assertIsInstance(node.value, ast.Constant)
                            self.assertIs(node.value.value, True)

    def test_model_exclusions_are_forwarded_to_every_scenario_context(self):
        for path in SCENARIOS:
            source = "\n".join(cells(path.name))
            for node in ast.walk(ast.parse(source)):
                if isinstance(node, ast.Call) and ast.unparse(node.func) == "ValidationContext.load":
                    with self.subTest(notebook=path.name):
                        self.assertIn("skipped_models", {keyword.arg for keyword in node.keywords})
                        self.assertIn("operation_overrides", {keyword.arg for keyword in node.keywords})


class MandatoryInitializationTests(unittest.TestCase):
    def test_actual_onboarding_uses_standard_azd_values_and_deploys_without_review_flags(self):
        name = "llm-backend-onboarding-runner.ipynb"
        namespace = configured(name)
        fixture = context_fixture()
        backends = fixture.config["llm_backends"]
        backends[0]["endpoint"] = "https://fixture.services.ai.azure.com"
        snapshot = {
            "AZURE_ENV_NAME": "fixture-env", "AZURE_SUBSCRIPTION_ID": "fixture-subscription",
            "AZURE_RESOURCE_GROUP": "fixture-rg", "AZURE_LOCATION": "fixture-location",
            "APIM_NAME": "fixture-apim", "LLM_BACKEND_CONFIG": json.dumps(backends),
        }
        apim = Mock()
        apim.return_value.apim_resource_name = "fixture-apim"
        apim.return_value.apim_resource_gateway_url = "https://gateway.example"
        apim.return_value.get_managed_identity_info.return_value = {
            "name": "fixture-identity", "resourceGroup": "fixture-rg",
        }
        namespace["APIMClientTool"] = apim
        with patch.object(validationtools, "_run_json", side_effect=[snapshot, fixture.account]) as commands, \
                patch.object(Path, "mkdir"), contextlib.redirect_stdout(io.StringIO()):
            exec(compile(cells(name)[1], name + ":initialize", "exec"), namespace)
        self.assertEqual(commands.call_count, 2)
        self.assertEqual(namespace["context"].provenance["llm_backends"], "azd")
        self.assertEqual(namespace["context"].config["environment"], "fixture-env")
        self.assertNotIn("approve_shared_routing", namespace)
        self.assertEqual(namespace["catalog"].operations("future-model"), ["chat"])
        namespace["llm_backends_config"] = namespace["context"].config["llm_backends"]
        preview = next(source for source in cells(name) if "backend_parameters = {" in source)
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            namespace["run_dir"] = Path(temporary)
            exec(compile(preview, name + ":preview", "exec"), namespace)
            self.assertTrue(namespace["backend_params"].is_file())
            deployment = next(source for source in cells(name) if "backend_outputs = deploy_contract" in source)
            namespace["deploy_contract"] = Mock(return_value={"backendIds": {"value": ["fixture"]}})
            apim.return_value.client.backend.list_by_service.return_value = [SimpleNamespace(name="fixture")]
            apim.return_value.client.policy_fragment.get.return_value.value = "<fragment/>"
            exec(compile(deployment, name + ":deploy", "exec"), namespace)
            namespace["deploy_contract"].assert_called_once()

    def test_missing_gateway_coordinates_stop_every_scenario_before_sdk(self):
        for path in SCENARIOS:
            namespace = configured(path.name)
            context = context_fixture()
            context.config.update({field: None for field in (
                "subscription_id", "resource_group", "location", "apim_name",
            )})
            with self.subTest(notebook=path.name), self.assertRaises(ValueError):
                initialize(path.name, namespace, context)

    def test_access_defaults_require_external_targets_but_not_a_project_token(self):
        name = "citadel-access-contracts-tests.ipynb"
        with patch.dict(os.environ, {"VALIDATION_FOUNDRY_PROJECT_TOKEN": ""}):
            namespace = configured(name)
        self.assertIs(namespace["use_keyvault_integration"], True)
        self.assertIs(namespace["use_foundry_integration"], True)
        namespace["keyvault"] = {key: "REPLACE" for key in namespace["keyvault"]}
        namespace["foundry"] = {key: "REPLACE" for key in namespace["foundry"]}
        with self.assertRaises(ValueError) as raised:
            initialize(name, namespace)
        for label in (
            "keyvault.subscriptionId", "keyvault.resourceGroupName", "keyvault.name",
            "foundry.subscriptionId", "foundry.resourceGroupName", "foundry.accountName",
            "foundry.projectName",
        ):
            self.assertIn(label, str(raised.exception))
        self.assertNotIn("REPLACE", str(raised.exception))
        self.assertNotIn("project_mi_token", str(raised.exception))
        self.assertEqual(namespace["keyvault"]["name"], "REPLACE", "Never substitute the hub vault.")

    def test_access_explicit_opt_out_does_not_require_unused_targets(self):
        name = "citadel-access-contracts-tests.ipynb"
        namespace = configured(name)
        namespace.update(use_keyvault_integration=False, use_foundry_integration=False)
        apim = Mock()
        apim.return_value.apim_resource_name = "fixture-apim"
        apim.return_value.apim_resource_gateway_url = "https://gateway.example"
        initialize(name, namespace, apim=apim)
        apim.assert_called_once()
        self.assertEqual(namespace["model"], "future-model")

    def test_access_embedded_placeholder_does_not_pass(self):
        name = "citadel-access-contracts-tests.ipynb"
        namespace = configured(name)
        namespace.update(use_foundry_integration=False, keyvault={
            "subscriptionId": "fixture", "resourceGroupName": "fixture", "name": "https://REPLACE/vault",
        })
        with self.assertRaises(ValueError) as raised:
            initialize(name, namespace)
        self.assertIn("keyvault.name", str(raised.exception))
        self.assertNotIn("https://", str(raised.exception))

    def test_alerting_requires_external_notification_input_not_discoverable_observability(self):
        name = "citadel-alerting-tests.ipynb"
        with self.assertRaises(ValueError) as raised:
            initialize(name, configured(name))
        self.assertIn("alerting.alert_email_address", str(raised.exception))
        self.assertNotIn("alerting.app_insights_name", str(raised.exception))

    def test_publication_aggregates_a2a_targets_and_observability(self):
        name = "citadel-publish-contract-tests.ipynb"
        with self.assertRaises(ValueError) as raised:
            initialize(name, configured(name))
        for label in ("a2a.foundry_account_name", "a2a.foundry_project_name", "a2a.foundry_agent_name"):
            self.assertIn(label, str(raised.exception))
        self.assertNotIn("publication.app_insights_name", str(raised.exception))

    def test_external_provider_and_alias_routing_default_to_azd_source_and_allowed_deployment(self):
        for name in ("citadel-model-aliases-tests.ipynb",
                     "llm-backend-onboarding-extended-providers-runner.ipynb"):
            namespace = configured(name)
            with self.subTest(notebook=name):
                if name.startswith("llm-backend-onboarding-extended"):
                    with self.assertRaisesRegex(ValueError, "external.*backend_endpoint_and_credentials") as raised:
                        initialize(name, namespace, apim=initialized_apim())
                    self.assertNotIn("source_parameters_file", str(raised.exception))
                    self.assertNotIn("approve_shared_routing", str(raised.exception))
                else:
                    initialize(name, namespace, apim=initialized_apim())
                self.assertIsNone(namespace["source_parameters_file"])
                self.assertIs(namespace["source_configuration_complete"], True)
                self.assertIs(namespace["approve_shared_routing"], True)
                self.assertEqual(namespace["context"].config["llm_backends"][0]["backendId"], "fixture")

    def test_base_onboarding_loads_data_without_treating_manual_approvals_as_missing(self):
        name = "llm-backend-onboarding-runner.ipynb"
        namespace = configured(name)
        self.assertNotIn("complete_backend_configuration", namespace)
        self.assertNotIn("approve_shared_routing", namespace)
        apim = Mock()
        apim.return_value.apim_resource_name = "fixture-apim"
        apim.return_value.apim_resource_gateway_url = "https://gateway.example"
        initialize(name, namespace, apim=apim)
        self.assertNotIn("complete_backend_configuration", namespace)
        self.assertNotIn("approve_shared_routing", namespace)
        self.assertEqual(namespace["context"].config["llm_backends"][0]["backendId"], "fixture")

    def test_agents_require_all_predecessor_records_before_sdk(self):
        name = "citadel-agent-frameworks-tests.ipynb"
        with self.assertRaises(ValueError) as raised:
            initialize(name, configured(name))
        for contract in ("Sales-Assistant", "HR-ChatAgent", "Support-Bot"):
            self.assertIn(f"contracts.{contract}.product_id", str(raised.exception))
            self.assertIn(f"contracts.{contract}.allowed_models", str(raised.exception))

    def test_jwt_defaults_never_request_device_codes_and_aggregate_credentials(self):
        name = "citadel-jwt-authentication-tests.ipynb"
        with patch.dict(os.environ, {"VALIDATION_ENTRA_CLIENT_SECRET": "", "VALIDATION_JWT_NO_ROLE_TOKEN": ""}):
            namespace = configured(name)
        self.assertIs(namespace["use_device_flow"], False)
        with self.assertRaises(ValueError) as raised:
            initialize(name, namespace)
        for label in ("entra.client_id", "entra.audience", "entra.client_secret", "jwt.no_role_token_fixture"):
            self.assertIn(label, str(raised.exception))

    def test_jwt_no_role_fixture_must_be_unexpired_and_have_no_roles(self):
        name = "citadel-jwt-authentication-tests.ipynb"
        for token in ("not-a-jwt", no_role_fixture(["Models.Read"]), no_role_fixture(expired=True)):
            namespace = configured(name)
            namespace.update(entra_client_secret="fixture-secret", no_role_token_fixture=token)
            context = context_fixture()
            context.config["entra_client_id"] = "fixture-client"
            with self.subTest(fixture=token[:9]), self.assertRaisesRegex(ValueError, "actual unexpired no-role JWT"):
                initialize(name, namespace, context)

    def test_jwt_device_selection_requires_fixture_not_a_prompt(self):
        name = "citadel-jwt-authentication-tests.ipynb"
        namespace = configured(name)
        namespace.update(token_source="device_flow", use_device_flow=True,
                         no_role_token_fixture=no_role_fixture(), device_token_fixture="")
        context = context_fixture()
        context.config["entra_client_id"] = "fixture-client"
        with self.assertRaises(ValueError) as raised:
            initialize(name, namespace, context)
        self.assertIn("jwt.device_token_fixture", str(raised.exception))
        self.assertNotIn("entra.client_secret", str(raised.exception))

    def test_jwt_device_fixture_flow_skips_secret_request_and_interactive_sdk(self):
        name = "citadel-jwt-authentication-tests.ipynb"
        namespace = configured(name)
        namespace.update(token_source="device_flow", use_device_flow=True, entra_client_secret="",
                         no_role_token_fixture=no_role_fixture(),
                         device_token_fixture=no_role_fixture(roles=["Models.Read"]))
        context = context_fixture()
        context.config["entra_client_id"] = "fixture-client"
        initialize(name, namespace, context)
        interactive = Mock(side_effect=AssertionError("Device prompt is forbidden"))
        with patch("requests.post", side_effect=AssertionError("Unused client secret flow")), \
                patch.dict(sys.modules, {"msal": SimpleNamespace(PublicClientApplication=interactive)}), \
                contextlib.redirect_stdout(io.StringIO()):
            exec(cells(name)[3], namespace)
            exec(cells(name)[4], namespace)
            exec(cells(name)[6], namespace)
        interactive.assert_not_called()
        self.assertEqual(namespace["active_token"], namespace["device_token_fixture"])

    def test_pii_requires_state_evidence_or_cosmos_before_deployment(self):
        name = "citadel-pii-processing-tests.ipynb"
        with self.assertRaises(ValueError) as raised:
            initialize(name, configured(name))
        self.assertIn("pii.cosmos_account_endpoint or pii_state_evidence", str(raised.exception))
        namespace = configured(name)
        namespace["pii_state_evidence"] = [{"id": "captured-event", "context": {}}]
        initialize(name, namespace)
        self.assertEqual(namespace["model_name"], "future-model")

    def test_image_missing_optional_negative_control_does_not_require_customization(self):
        name = "citadel-image-models-tests.ipynb"
        namespace = configured(name)
        initialize(name, namespace, apim=initialized_apim())
        self.assertIs(namespace["run_backend_onboarding"], True)
        self.assertTrue(namespace["image_ready"])
        self.assertEqual(namespace["openai_image_model"], "future-model")

    def test_affinity_without_multi_backend_pool_is_skipped_not_a_parameter_error(self):
        name = "citadel-session-affinity-tests.ipynb"
        namespace = configured(name)
        initialize(name, namespace, apim=initialized_apim())
        self.assertFalse(namespace["affinity_ready"])
        self.assertTrue(any(result.status == "SKIP" for result in namespace["run"].results))

    def test_affinity_default_onboarding_can_add_session_flags_without_customization(self):
        name = "citadel-session-affinity-tests.ipynb"
        backends = [{
            "backendId": backend, "backendType": "ai-foundry", "protocol": "openai-compat",
            "supportedModels": [{"name": "future-model", "capabilities": ["responses"]}],
        } for backend in ("east", "west")]
        namespace = configured(name)
        initialize(name, namespace, context_fixture(backends=backends), apim=initialized_apim())
        self.assertIs(namespace["run_backend_onboarding"], True)
        self.assertIs(namespace["backend_configuration_complete"], True)
        self.assertTrue(namespace["affinity_ready"])

    def test_strict_unannotated_catalog_stops_before_apim_even_with_access_opt_out(self):
        name = "citadel-access-contracts-tests.ipynb"
        namespace = configured(name)
        namespace.update(use_keyvault_integration=False, use_foundry_integration=False)
        context = context_fixture(capabilities={})
        context.catalog = validationtools.ModelCatalog(context.config["llm_backends"], infer_operations=False)
        with self.assertRaises(ValueError):
            initialize(name, namespace, context)


class SetupRestartTests(unittest.TestCase):
    def install(self, before, after, restart_required=False):
        namespace = {
            "utils": utils, "subprocess": SimpleNamespace(run=Mock()),
            "pip_command": ["fixture-python", "-m", "pip"], "requirements_path": Path("requirements.txt"),
            "md": SimpleNamespace(distributions=lambda: [
                SimpleNamespace(metadata={"Name": name}, version=version) for name, version in after.items()
            ]),
            "dependency_versions_before_install": before,
            "_validation_restart_required": restart_required,
        }
        with contextlib.redirect_stdout(io.StringIO()):
            exec(cells("citadel-environment-setup.ipynb")[2], namespace)
        return namespace

    def test_dependency_changes_stop_run_all_for_restart(self):
        with self.assertRaisesRegex(RuntimeError, "STOP Run All: restart the kernel"):
            self.install({"requests": "1"}, {"requests": "2"})

    def test_unchanged_dependencies_allow_run_all_verification(self):
        namespace = self.install({"requests": "1"}, {"requests": "1"})
        namespace["subprocess"].run.assert_called_once()

    def test_rerunning_install_without_restart_cannot_bypass_the_stop(self):
        with self.assertRaisesRegex(RuntimeError, "STOP Run All: restart the kernel"):
            self.install({"requests": "2"}, {"requests": "2"}, restart_required=True)

    def test_verification_cannot_bypass_a_pending_restart(self):
        namespace = {"utils": utils, "_validation_restart_required": True}
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(RuntimeError, "STOP verification"):
            exec(cells("citadel-environment-setup.ipynb")[3], namespace)


if __name__ == "__main__":
    unittest.main()
