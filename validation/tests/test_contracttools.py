"""Offline contract tests; compiler fixtures use ignored, explicitly removed runs."""

import copy
import contextlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import unittest
from unittest.mock import patch
import uuid
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))
import contracttools as ct
from consumerhelpers import contract_identifiers


def compiled(parameters=None, outputs=None, definitions=None, variables=None):
    return {
        "templateJson": json.dumps({
            "parameters": definitions or {},
            "variables": variables or {},
            "outputs": outputs or {"result": {"type": "string", "value": "ok"}},
        }),
        "parametersJson": json.dumps({
            "parameters": {k: {"value": v} for k, v in (parameters or {}).items()},
        }),
    }


class ArtifactTestCase(unittest.TestCase):
    def setUp(self):
        self.directory = ROOT / "validation" / ".runs" / "contracttools-tests" / uuid.uuid4().hex
        self.directory.mkdir(parents=True)
        self.template = self.directory / "fixture.bicep"
        self.template.write_text(
            "targetScope = 'subscription'\n"
            "param data object\n"
            "@secure()\nparam opaque string = ''\n"
            "output result object = data\n",
            encoding="utf-8",
        )

    def tearDown(self):
        shutil.rmtree(self.directory)


class RenderingTests(ArtifactTestCase):
    def test_scalars_and_escaping(self):
        self.assertEqual(ct.render_bicep(None), "null")
        self.assertEqual(ct.render_bicep(True), "true")
        self.assertEqual(ct.render_bicep(False), "false")
        self.assertEqual(ct.render_bicep(-10), "-10")
        self.assertEqual(ct.render_bicep("'\\\r\n\t${x}"),
                         r"'\'\\\r\n\t\${x}'")
        self.assertIn(r"\u{0}", ct.render_bicep("\0"))
        self.assertEqual(ct.render_bicep("汉字🧪"), "'汉字🧪'")

    def test_nested_values_preserve_order_and_input(self):
        data = {"z": [None, True, {"quote'": "${x}"}], "a": {"x": 12}}
        original = copy.deepcopy(data)
        text = ct.render_bicep(data)
        self.assertLess(text.index("'z'"), text.index("'a'"))
        self.assertIn("'quote\\'': '\\${x}'", text)
        self.assertEqual(data, original)

    def test_unsupported_values_fail_instead_of_coercing(self):
        for value in ({1: "x"}, {1}, Path("a"), object()):
            with self.subTest(value=type(value).__name__), self.assertRaises(TypeError):
                ct.render_bicep(value)
        for value in (2**63, float("nan"), float("inf")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                ct.render_bicep(value)
        self.assertEqual(ct.render_bicep(-(2**63)), "(-9223372036854775807 - 1)")
        self.assertEqual(ct.render_bicep(1.25), "json('1.25')")

    def test_write_parameters_resolves_using_and_preserves_nested_fields(self):
        parameters = {"data": {"custom-property": [{"new": "kept"}], "enabled": False}}
        original = copy.deepcopy(parameters)
        path = ct.write_parameters(self.template, parameters, self.directory / "run")
        text = path.read_text(encoding="utf-8")
        self.assertTrue(text.startswith("using '../fixture.bicep'"))
        self.assertIn("'custom-property'", text)
        self.assertIn("'new': 'kept'", text)
        self.assertEqual(parameters, original)
        self.assertEqual(path.suffix, ".bicepparam")

    def test_invalid_parameters_never_create_artifacts(self):
        for parameters in ({"bad-name": 1}, {"": 1}, {"payload": object()}):
            with self.subTest(parameters=parameters), self.assertRaises((ct.ContractError, TypeError)):
                ct.write_parameters(self.template, parameters, self.directory / "bad")
            self.assertFalse((self.directory / "bad").exists())
        with self.assertRaises(ct.ContractError):
            ct.write_parameters(self.directory / "missing.bicep", {}, self.directory / "bad")

    def test_policy_file_references_and_manifest(self):
        xml = ct.access_policy(["model"], 100, 1000, "Monthly")
        parameters = {"data": {"services": [{"policyXml": xml}], "nested": [xml]}}
        original = copy.deepcopy(parameters)
        artifact = ct.prepare_artifact(
            self.template, parameters, self.directory / "run",
            policies={"policies/product.xml": xml},
        )
        text = artifact.params_file.read_text(encoding="utf-8")
        self.assertEqual(text.count("loadTextContent('policies/product.xml')"), 2)
        self.assertEqual((artifact.params_file.parent / "policies" / "product.xml")
                         .read_text(encoding="utf-8"), xml)
        self.assertEqual(parameters, original)
        manifest = json.loads(artifact.manifest_file.read_text(encoding="utf-8"))
        self.assertEqual(manifest["resources"], [])
        self.assertEqual(manifest["policies"], ["policies/product.xml"])
        with self.assertRaises(ct.ContractError):
            ct.prepare_artifact(self.template, parameters, artifact.params_file.parent)

    def test_policy_path_escape_is_rejected(self):
        for filename in ("../outside.xml", r"..\outside.xml", r"C:\outside.xml",
                         "not-xml.txt", r"C:relative.xml"):
            with self.subTest(filename=filename), self.assertRaises(ct.ContractError):
                ct.PolicyReference(filename)


class CredentialTests(ArtifactTestCase):
    def test_inline_secrets_rejected_before_any_write(self):
        for key in ("api-key", "subscriptionKey", "Authorization", "client_secret",
                    "password", "token", "key", "rotationKeyOverride"):
            with self.subTest(key=key), self.assertRaises(ct.ContractError):
                ct.write_parameters(self.template, {"data": [{key: "sensitive"}]},
                                    self.directory / "unsafe")
        self.assertFalse((self.directory / "unsafe").exists())

    def test_known_secret_value_forms_rejected(self):
        for value in ("Bearer some-token", "eyJhbGciOiJ9.eyJzdWIiOiIxIn0.signature",
                      "-----BEGIN PRIVATE KEY-----", "https://example/?sig=sensitive",
                      "AccountKey=sensitive", "https://example/?api_key=sensitive"):
            with self.subTest(value=value), self.assertRaises(ct.ContractError):
                ct.write_parameters(self.template, {"data": {"payload": value}},
                                    self.directory / "unsafe")

    def test_inline_secure_parameter_with_unrecognizable_name_rejected(self):
        with self.assertRaises(ct.ContractError):
            ct.write_parameters(self.template, {"data": {}, "opaque": "sensitive"},
                                self.directory / "unsafe")
        self.assertFalse((self.directory / "unsafe").exists())

    def test_references_and_nonsensitive_secret_metadata_allowed(self):
        parameters = {"data": {
            "apiKeySecretName": "provider-key", "keyVaultApiKeySecretName": "key",
            "keyVaultSecretUri": "https://example.vault.azure.net/secrets/key",
            "apiKey": "{{provider-key}}", "tokensPerMinute": 100,
            "tokenQuota": 1000, "useTargetAzureKeyVault": True,
            "rotationKeyOverride": "", "keyRotationEnabled": False,
        }}
        self.assertTrue(ct.write_parameters(self.template, parameters,
                                           self.directory / "safe").is_file())
        ct._compiled_docs(compiled({"apiKey": "{{provider-key}}",
                                   "rotationKeyOverride": ""}))

    def test_compiled_secure_parameter_rejected(self):
        with self.assertRaises(ct.ContractError):
            ct._compiled_docs(compiled({"opaque": "sensitive"},
                                       definitions={"opaque": {"type": "secureString"}}))

    def test_literal_policy_credentials_rejected_and_named_values_allowed(self):
        for xml in (
            '<policies><inbound><set-header name="api-key"><value>secret</value>'
            '</set-header></inbound></policies>',
            '<policies><inbound><set-variable name="clientSecret" value="secret" />'
            '</inbound></policies>',
        ):
            with self.subTest(xml=xml), self.assertRaises(ct.ContractError):
                ct.write_parameters(self.template, {"data": {"policyXml": xml}},
                                    self.directory / "unsafe")
        xml = ('<policies><inbound><set-header name="api-key">'
               '<value>{{provider-key}}</value></set-header></inbound></policies>')
        self.assertTrue(ct.write_parameters(self.template, {"data": {"policyXml": xml}},
                                           self.directory / "safe").is_file())

    def test_preview_checks_resolved_parameters_and_does_not_leak_errors(self):
        path = ct.write_parameters(self.template, {"data": {}}, self.directory / "run")
        path.write_text("using '../fixture.bicep'\nparam data = {apiKey: 'secret'}\n",
                        encoding="utf-8")
        with patch.object(ct, "_run_az", return_value=compiled({"data": {"apiKey": "secret"}})):
            with self.assertRaises(ct.ContractError) as error:
                ct.preview(path)
        self.assertNotIn("'secret'", str(error.exception))


class PolicyTests(unittest.TestCase):
    def test_order_jwt_rbac_capacity_pii_and_outbound(self):
        extra = '<include-fragment fragment-id="custom" />'
        pii = '<include-fragment fragment-id="pii-anonymization" />'
        outbound = '<include-fragment fragment-id="pii-restoration" />'
        xml = ct.access_policy(["model-a", "model-b"], 100, 500, "Daily", extra,
                               jwt_required=True, pii_inbound=pii, pii_outbound=outbound)
        root = ET.fromstring(xml)
        children = list(root.find("inbound"))
        self.assertEqual([n.tag for n in children], [
            "base", "set-variable", "include-fragment", "set-variable",
            "include-fragment", "llm-token-limit", "set-variable",
            "include-fragment", "include-fragment",
        ])
        self.assertEqual(children[1].attrib, {"name": "jwtRequired", "value": "true"})
        self.assertEqual(children[3].get("value"), "model-a,model-b")
        self.assertEqual(children[4].get("fragment-id"), "validate-model-access")
        self.assertEqual(children[5].get("tokens-per-minute"), "100")
        self.assertEqual(children[5].get("token-quota"), "500")
        self.assertEqual(root.find("outbound")[1].get("fragment-id"), "pii-restoration")

    def test_xml_escaping_unrestricted_models_and_explicit_jwt_false(self):
        xml = ct.access_policy(['model&<"'], 1, 1, "Hourly", jwt_required=False)
        root = ET.fromstring(xml)
        self.assertEqual(root.find("inbound")[3].get("value"), 'model&<"')
        self.assertIn('name="jwtRequired" value="false"', xml)
        self.assertNotIn("jwtRequired", ct.access_policy([], 1, 1, "Monthly"))

    def test_invalid_capacity_period_and_extra_xml_fail(self):
        for tpm, quota, period in ((0, 1, "Monthly"), (True, 1, "Monthly"),
                                   (1, -1, "Monthly"), (1, 1, "Wrong")):
            with self.subTest(tpm=tpm, quota=quota, period=period), self.assertRaises(ValueError):
                ct.access_policy([], tpm, quota, period)
        with self.assertRaises(ct.ContractError):
            ct.access_policy([], 1, 1, "Monthly", "<broken>")


class CLITests(ArtifactTestCase):
    def test_subscription_metadata_survives_secret_reference_filter_and_resolves_exact_key_name(self):
        path = ct.write_parameters(self.template, {"data": {}}, self.directory / "run")
        product = "LLM-Validation-UnifiedFixture-DEV"
        subscription = product + "-SUB-01"
        template_outputs = {
            "products": {"type": "array", "value": [{"productId": product}]},
            "subscriptions": {
                "type": "array",
                "copy": {"count": 1, "input": {
                    "name": subscription, "productId": product,
                    "keyVaultApiKeySecretName": "[variables('serviceSecretPlans')[copyIndex()].keySecretName]",
                }},
            },
            "foundryConnections": {
                "type": "array",
                "copy": {"count": 1, "input": {
                    "connectionName": "Hub-HR-ChatAgent-DEV-LLM",
                    "targetUrl": "[variables('serviceSecretPlans')[copyIndex()].foundryApiIndex]",
                    "authType": "ProjectManagedIdentity",
                }},
            },
            "endpoints": {"type": "array", "value": [{"apiKey": "fixture-key-not-for-output"}]},
        }
        fixture = compiled(outputs=template_outputs, variables={
            "serviceSecretPlans": [{"keySecretName": "contract-key-reference"}],
        })
        deploy_query = []

        def run(arguments):
            if arguments[:2] == ["bicep", "build-params"]:
                return fixture
            query = arguments[arguments.index("--query") + 1]
            deploy_query.append(query)
            outputs = {"products": {"type": "Array", "value": [{"productId": product}]}}
            if '"subscriptions":' in query:
                outputs["subscriptions"] = {"type": "Array", "value": [{
                    "name": subscription, "productId": product,
                    "keyVaultApiKeySecretName": "contract-key-reference",
                }]}
            if '"foundryConnections":' in query:
                outputs["foundryConnections"] = {"type": "Array", "value": [{
                    "connectionName": "Hub-HR-ChatAgent-DEV-LLM", "authType": "ProjectManagedIdentity",
                }]}
            return {"state": "Succeeded", "outputs": outputs}

        output = io.StringIO()
        with patch.object(ct, "_run_az", side_effect=run), contextlib.redirect_stdout(output):
            outputs = ct.deploy_contract(path, "eastus", "fixture")
            self.assertEqual(contract_identifiers(outputs, product), (product, subscription))
        self.assertIn("properties.outputs.subscriptions.value[].{", deploy_query[0])
        self.assertIn("name:name", deploy_query[0])
        self.assertIn("productId:productId", deploy_query[0])
        self.assertNotIn("apiKey:", deploy_query[0])
        self.assertNotIn("primaryKey:", deploy_query[0])
        self.assertNotIn("fixture-key-not-for-output", output.getvalue())
        self.assertEqual(outputs["subscriptions"]["value"][0]["keyVaultApiKeySecretName"],
                         "contract-key-reference")
        self.assertEqual(outputs["foundryConnections"]["value"][0]["connectionName"],
                         "Hub-HR-ChatAgent-DEV-LLM")

    def test_compile_uses_actual_file_stdout_and_no_cloud(self):
        path = ct.write_parameters(self.template, {"data": {}}, self.directory / "run")
        with patch.object(ct, "_run_az", return_value=compiled()) as run:
            ct.compile_parameters(path)
        self.assertEqual(run.call_args.args[0],
                         ["bicep", "build-params", "--file", str(path.resolve()), "--stdout"])
        self.assertFalse(list(self.directory.rglob("*.json")))

    def test_subprocess_failure_and_malformed_json_are_not_echoed(self):
        for result in (subprocess.CompletedProcess([], 1, "secret-key", "secret-key"),
                       subprocess.CompletedProcess([], 0, "secret-key", "")):
            with self.subTest(code=result.returncode), \
                    patch.object(ct.shutil, "which", return_value="az.cmd"), \
                    patch.object(ct.subprocess, "run", return_value=result), \
                    self.assertRaises(ct.ContractError) as error:
                ct._run_az(["bicep", "build-params"])
            self.assertNotIn("secret-key", str(error.exception))

    def test_subprocess_uses_utf8_and_preserves_isolated_msi_launcher(self):
        executable = ROOT / "fake-cli" / "wbin" / "az.cmd"
        with patch.object(ct.shutil, "which", return_value=str(executable)), \
                patch.object(Path, "is_file", return_value=True), \
                patch.object(ct.subprocess, "run", return_value=subprocess.CompletedProcess(
                    [], 0, '{"result": "汉字"}', ""
                )) as run:
            self.assertEqual(ct._run_az(["bicep", "version"])["result"], "汉字")
        arguments, kwargs = run.call_args
        if sys.platform == "win32":
            self.assertEqual(arguments[0][1:6], ["-IB", "-X", "utf8", "-m", "azure.cli"])
        self.assertEqual(kwargs["encoding"], "utf-8")
        self.assertEqual(kwargs["env"]["PYTHONIOENCODING"], "utf-8")

    def test_deploy_compiles_first_returns_raw_outputs_and_projects_no_secrets(self):
        path = ct.write_parameters(self.template, {"data": {}}, self.directory / "run")
        template_outputs = {
            "products": {"type": "array", "value": [{"productId": "product"}]},
            "endpoints": {"type": "array", "value": [{"apiKey": "generated"}]},
            "primaryKey": {"type": "string", "value": "generated"},
            "hidden": {"type": "object", "value": "[variables('hiddenValue')]"},
            "dynamic": {"type": "string", "value": "[listKeys('resource', 'api').key]"},
            "opaqueOutput": {"type": "string", "value": "[parameters('opaque')]"},
        }
        response = {"state": "Succeeded", "outputs": {
            "products": {"type": "Array", "value": [{"productId": "product"}]},
        }}
        with patch.object(ct, "_run_az", side_effect=[
            compiled(outputs=template_outputs, variables={"hiddenValue": {"password": "secret"}},
                     definitions={"opaque": {"type": "secureString"}}),
            response,
        ]) as run:
            outputs = ct.deploy_contract(path, "eastus", "test", required_outputs=["products"])
        self.assertEqual(outputs["products"]["value"][0]["productId"], "product")
        self.assertEqual(run.call_count, 2)
        command = run.call_args.args[0]
        self.assertEqual(command[:3], ["deployment", "sub", "create"])
        self.assertIn(str(path.resolve()), command)
        query = command[command.index("--query") + 1]
        self.assertIn("subscriptionName:subscriptionName", query)
        self.assertNotIn("apiKey", query)
        self.assertNotIn("primaryKey", query)
        self.assertNotIn("hidden", query)
        self.assertNotIn("dynamic", query)
        self.assertNotIn("opaqueOutput", query)

    def test_deployment_state_output_validation_and_empty_required_outputs(self):
        path = ct.write_parameters(self.template, {"data": {}}, self.directory / "run")
        for response in ({"state": "Failed", "outputs": {}},
                         {"state": "Succeeded", "outputs": []},
                         {"state": "Succeeded", "outputs": {"result": "wrong"}},
                         {"state": "Succeeded", "outputs": {}},
                         {"state": "Succeeded", "outputs": {
                             "result": {"type": "String", "value": ""}}}):
            with self.subTest(response=response), patch.object(
                ct, "_run_az", side_effect=[compiled(), response]
            ), self.assertRaises(ct.ContractError):
                ct.deploy_contract(path, "eastus", "test", required_outputs=["result"])

    def test_invalid_required_output_fails_before_cloud(self):
        path = ct.write_parameters(self.template, {"data": {}}, self.directory / "run")
        with patch.object(ct, "_run_az", return_value=compiled()) as run:
            with self.assertRaises(ct.ContractError):
                ct.deploy_contract(path, "eastus", "test", required_outputs=["missing"])
            self.assertEqual(run.call_count, 1)

    def test_unexpected_nested_credentials_are_removed(self):
        path = ct.write_parameters(self.template, {"data": {}}, self.directory / "run")
        result = {"state": "Succeeded", "outputs": {
            "opaque": {"type": "SecureString", "value": "secret"},
            "result": {
            "type": "Object", "value": {
                "name": "safe", "apiKey": "secret", "inner": [{"password": "secret"}],
                "text": "Bearer confidential",
            }}}}
        with patch.object(ct, "_run_az", side_effect=[compiled(), result]):
            outputs = ct.deploy_contract(path, "eastus", "test")
        self.assertNotIn("secret", json.dumps(outputs))
        self.assertNotIn("confidential", json.dumps(outputs))
        self.assertEqual(outputs["result"]["value"]["name"], "safe")


class OwnershipTests(ArtifactTestCase):
    def test_cleanup_requires_explicit_creation_not_deployment_success(self):
        artifact = ct.prepare_artifact(self.template, {"data": {}}, self.directory / "run")
        with patch.object(ct, "deploy_contract", return_value={
            "products": {"type": "Array", "value": [{"productId": "existing"}]},
        }):
            artifact.deploy("eastus", "deployment")
        self.assertEqual(artifact.cleanup_candidates(), [])
        base = "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ApiManagement/service/apim/products/"
        artifact.record_resource(base + "new", created=True)
        artifact.record_resource(base + "existing", created=False)
        artifact.record_resource(base + "shared", created=True, shared=True)
        artifact.record_resource(base + "predecessor", created=True, predecessor=True)
        self.assertEqual(artifact.cleanup_candidates(), [base + "new"])
        artifact.record_resource((base + "new").upper(), created=False)
        artifact.record_resource(base + "new", created=True)
        self.assertEqual(artifact.cleanup_candidates(), [])

    def test_ownership_rejects_deployment_handles_and_broad_scopes(self):
        artifact = ct.prepare_artifact(self.template, {"data": {}}, self.directory / "run")
        for resource_id in ("deployment-name", "/subscriptions/sub", "/subscriptions/sub/resourceGroups/rg"):
            with self.subTest(resource_id=resource_id), self.assertRaises(ct.ContractError):
                artifact.record_resource(resource_id, created=True)
        artifact.manifest_file.write_text(json.dumps({"params_file": "other"}), encoding="utf-8")
        with self.assertRaises(ct.ContractError):
            artifact.cleanup_candidates()


@unittest.skipUnless(shutil.which("az"), "Local Azure CLI/Bicep compiler unavailable")
class CompilerFixtureTests(ArtifactTestCase):
    def test_deployment_query_parses_in_actual_cli_without_cloud(self):
        fixture = compiled(outputs={
            "products": {"type": "array", "value": []},
            "endpoints": {"type": "array", "value": [{"apiKey": "unused"}]},
            "subscriptions": {"type": "array", "value": [
                {"productId": "fixture-product", "name": "fixture-subscription"},
            ]},
        })
        with patch.object(ct, "compile_parameters", return_value=fixture), patch.object(
            ct, "_run_az", return_value={"state": "Succeeded", "outputs": {}}
        ) as run:
            ct.deploy_contract(self.directory / "not-used.bicepparam", "eastus", "query-check")
        command = run.call_args.args[0]
        query = command[command.index("--query") + 1]
        self.assertIsInstance(ct._run_az(["version", "--query", query]), dict)
        self.assertNotIn("apiKey", query)
        self.assertIn("subscriptionName:subscriptionName", query)

    def test_real_compiler_roundtrips_nested_strings_and_edited_parameters(self):
        data = {
            "text": "'\\\r\n\t${notInterpolation} 汉字🧪\0",
            "strange'${key}": [True, False, None, {}, [], {"count": 42}],
            "minimum": -(2**63), "maximum": 2**63 - 1, "fraction": 1.25,
        }
        path = ct.write_parameters(self.template, {"data": data}, self.directory / "run")
        _, params = ct._compiled_docs(ct.compile_parameters(path))
        self.assertEqual(params["parameters"]["data"]["value"], data)
        edited = copy.deepcopy(data)
        edited["text"] = "manually edited"
        path.write_text(path.read_text(encoding="utf-8").replace(
            ct.render_bicep(data["text"]), ct.render_bicep(edited["text"])),
            encoding="utf-8",
        )
        _, params = ct._compiled_docs(ct.compile_parameters(path))
        self.assertEqual(params["parameters"]["data"]["value"], edited)
        self.assertIn("manually edited", ct.preview(path))
        self.assertFalse(list(path.parent.glob("*.json")))

    def test_real_compiler_loads_policy_and_rejects_post_generation_secret(self):
        xml = ct.access_policy(["model"], 100, 1000, "Monthly")
        inline_path = ct.write_parameters(self.template, {"data": {"policyXml": xml}},
                                          self.directory / "inline")
        self.assertIn("<policies>", ct.preview(inline_path))
        artifact = ct.prepare_artifact(self.template, {"data": {"policyXml": xml}},
                                       self.directory / "run", {"product.xml": xml})
        _, params = ct._compiled_docs(artifact.compile())
        self.assertEqual(params["parameters"]["data"]["value"]["policyXml"], xml)
        artifact.params_file.write_text(
            "using '../fixture.bicep'\nparam data = {apiKey: 'confidential'}\n",
            encoding="utf-8",
        )
        with self.assertRaises(ct.ContractError):
            artifact.compile()

    def test_actual_access_backend_and_publish_templates_compile_without_cloud(self):
        coordinates = {
            "subscriptionId": "11111111-1111-1111-1111-111111111111",
            "resourceGroupName": "rg-offline", "name": "apim-offline",
        }
        cases = {
            "citadel-access-contracts": {
                "apim": coordinates, "keyVault": {**coordinates, "name": "kv-offline"},
                "useTargetAzureKeyVault": True,
                "useTargetFoundry": True,
                "foundry": {
                    **coordinates, "accountName": "foundry-offline", "projectName": "project-offline",
                },
                "foundryConfig": {"authType": "ProjectManagedIdentity"},
                "useCase": {"businessUnit": "Test", "useCaseName": "Offline", "environment": "DEV"},
                "apiNameMapping": {"LLM": ["universal-llm-api"]},
                "services": [{
                    "code": "LLM", "apiKeySecretName": "offline-key",
                    "endpointSecretName": "offline-endpoint",
                    "policyXml": ct.access_policy(["offline-model"], 100, 1000, "Monthly"),
                }],
            },
            "llm-backend-onboarding": {
                "apim": coordinates,
                "apimManagedIdentity": {**coordinates, "name": "identity-offline"},
                "llmBackendConfig": [{
                    "backendId": "offline-backend", "backendType": "azure-openai",
                    "endpoint": "https://offline.openai.azure.com/",
                    "authType": "managed-identity",
                    "supportedModels": [{"name": "offline-model", "capacity": 1}],
                    "priority": 1, "weight": 100,
                }],
            },
            "citadel-publish-contracts": {
                "apim": coordinates,
                "publishAssets": [{
                    "assetType": "mcp-from-api", "name": "offline-tool",
                    "displayName": "Offline tool", "description": "Fixture only",
                    "path": "offline", "sourceApiName": "weather-api",
                    "operationNames": ["get-weather"],
                    "forwardSubscriptionKeyToSource": True,
                }],
            },
        }
        for directory, parameters in cases.items():
            with self.subTest(template=directory):
                template = ROOT / "bicep" / "infra" / directory / "main.bicep"
                path = ct.write_parameters(template, parameters, self.directory / directory)
                docs = ct.compile_parameters(path)
                self.assertEqual(json.loads(docs["parametersJson"])["parameters"],
                                 {k: {"value": v} for k, v in parameters.items()})
                self.assertTrue(json.loads(docs["templateJson"])["resources"])
                self.assertFalse(list(path.parent.glob("*.json")))
                if directory == "citadel-access-contracts":
                    prefix = json.loads(docs["templateJson"])["variables"]["foundryConnectionPrefix"]
                    self.assertIn("tryGet(parameters('foundryConfig'), 'connectionNamePrefix')", prefix)
                    self.assertNotIn("connectionNamePrefix", parameters["foundryConfig"])
                    self.assert_safe_access_subscription_projection(path, docs)

    def assert_safe_access_subscription_projection(self, path, docs):
        product = "LLM-Test-Offline-DEV"
        subscription = product + "-SUB-01"
        arm_response = {"properties": {
            "provisioningState": "Succeeded", "outputs": {
                "products": {"type": "Array", "value": [{"productId": product}]},
                "subscriptions": {"type": "Array", "value": [{
                    "name": subscription, "productId": product,
                    "keyVaultApiKeySecretName": "offline-key-reference",
                    "keyVaultEndpointSecretName": "offline-endpoint-reference",
                    "keyVaultEndpointSecretNames": ["offline-endpoint-reference"],
                    "primaryKey": "fake-value-must-not-be-projected",
                }]},
                "endpoints": {"type": "Array", "value": [{
                    "productId": product, "subscriptionName": subscription,
                    "apiKey": "fake-value-must-not-be-projected",
                }]},
                "foundryConnections": {"type": "Array", "value": [{
                    "code": "LLM", "connectionName": "Hub-Test-Offline-DEV-LLM",
                    "targetUrl": "https://offline.azure-api.net/models",
                    "foundryAccount": "foundry-offline", "foundryProject": "project-offline",
                    "authType": "ProjectManagedIdentity",
                    "managedIdentityAudience": "https://cognitiveservices.azure.com",
                    "customHeaders": {"api-key": "fake-value-must-not-be-projected"},
                    "credentials": {"key": "fake-value-must-not-be-projected"},
                }]},
            },
        }}
        definitions = json.loads(docs["templateJson"])["outputs"]
        defaults = {"array": [], "object": {}, "string": "", "bool": False, "int": 0}
        arm_response["properties"]["outputs"] = {
            **{key: {"type": definition["type"],
                     "value": copy.deepcopy(defaults.get(definition["type"].lower()))}
               for key, definition in definitions.items()},
            **arm_response["properties"]["outputs"],
        }
        run_az = ct._run_az
        queries = []

        def project_using_actual_local_cli(arguments):
            self.assertEqual(arguments[:3], ["deployment", "sub", "create"])
            query = arguments[arguments.index("--query") + 1]
            queries.append(query)
            # az version is local; the literal supplies data to its JMESPath parser.
            return run_az(["version", "--query", "`" + json.dumps(arm_response) + "` | " + query])

        output = io.StringIO()
        with patch.object(ct, "compile_parameters", return_value=docs), \
                patch.object(ct, "_run_az", side_effect=project_using_actual_local_cli), \
                contextlib.redirect_stdout(output):
            outputs = ct.deploy_contract(path, "eastus", "offline",
                                         required_outputs=("products", "subscriptions", "foundryConnections"))
        self.assertEqual(contract_identifiers(outputs, product), (product, subscription))
        self.assertEqual(outputs["subscriptions"]["value"][0]["keyVaultApiKeySecretName"],
                         "offline-key-reference")
        connection = outputs["foundryConnections"]["value"][0]
        self.assertEqual(connection["connectionName"], "Hub-Test-Offline-DEV-LLM")
        self.assertEqual(connection["authType"], "ProjectManagedIdentity")
        self.assertEqual(connection["foundryProject"], "project-offline")
        self.assertNotIn("fake-value-must-not-be-projected", json.dumps(outputs))
        self.assertNotIn("fake-value-must-not-be-projected", output.getvalue())
        self.assertNotIn("apiKey:", queries[0])
        self.assertNotIn("primaryKey:", queries[0])
        self.assertNotIn("customHeaders:", queries[0])
        self.assertNotIn("credentials:", queries[0])


if __name__ == "__main__":
    unittest.main()
