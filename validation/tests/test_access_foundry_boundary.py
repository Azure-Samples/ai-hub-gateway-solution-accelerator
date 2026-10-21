"""Access-contract setup does not require a manually acquired project-MI token."""
import contextlib
import io
import json
import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))
import validationtools
import requests
from test_external_defaults import apim_fixture, cells, snapshot


class FoundryTokenBoundaryTests(unittest.TestCase):
    def test_notebook_no_longer_exposes_a_manual_project_token_input(self):
        source = "\n".join(cells("access-contracts"))
        self.assertNotIn("project_mi_token", source)
        self.assertNotIn("VALIDATION_FOUNDRY_PROJECT_TOKEN", source)

    def test_token_free_initialization_preserves_auth_and_defers_only_identity_requests(self):
        namespace = {}
        values = snapshot()
        account = {"id": "fixture-sub", "tenantId": "fixture-tenant"}
        apim = apim_fixture()
        with contextlib.redirect_stdout(io.StringIO()), patch.object(Path, "mkdir"), \
                patch.dict(os.environ, {"VALIDATION_FOUNDRY_PROJECT_TOKEN": ""}):
            exec(cells("access-contracts")[0], namespace)
            namespace["keyvault"] = json.loads(values["VALIDATION_EXTERNAL_KEYVAULT"])
            namespace["foundry"] = json.loads(values["VALIDATION_EXTERNAL_FOUNDRY"])
            namespace["APIMClientTool"] = Mock(return_value=apim)
            with patch.object(validationtools, "_run_json", side_effect=[values, account]):
                exec(cells("access-contracts")[1], namespace)
            self.assertNotIn("project_mi_token", namespace)
            exec(cells("access-contracts")[2], namespace)
            parameters = []

            def write(template, data, directory):
                parameters.append(data)
                return SimpleNamespace(read_text=lambda **kwargs: "Editable parameter preview")

            namespace["write_parameters"] = write
            exec(cells("access-contracts")[3], namespace)
            self.assertEqual(len(parameters), 3)
            foundry_parameter = next(item for item in parameters if item["useTargetFoundry"])
            self.assertEqual(foundry_parameter["foundryConfig"]["connectionNamePrefix"], "")
            self.assertEqual(foundry_parameter["foundryConfig"]["authType"], "ProjectManagedIdentity")
            foundry_xml = ElementTree.fromstring(foundry_parameter["services"][0]["policyXml"])
            self.assertEqual(foundry_xml.find(".//set-variable[@name='jwtRequired']").get("value"), "true")
            policies = {
                contract["product_id"]: parameter["services"][0]["policyXml"]
                for contract, parameter in zip(namespace["access_contracts"], parameters)
            }
            def get_policy(rg, service, product, policy_id):
                self.assertEqual(policy_id, "policy")
                return SimpleNamespace(value=policies[product])
            apim.client.product_policy.get.side_effect = get_policy
            foundry_product = next(contract["product_id"] for contract in namespace["access_contracts"]
                                   if contract["use_foundry"])
            direct_contracts = {contract["product_id"]: contract for contract in namespace["access_contracts"]
                                if not contract["use_foundry"]}

            def key(name):
                self.assertNotEqual(name, foundry_product + "-SUB-01",
                                    "Direct consumption must not acquire the Foundry identity-protected key")
                return name

            apim.get_subscription_key.side_effect = key

            def request(url, headers, **kwargs):
                self.assertNotIn("Authorization", headers)
                product = headers["api-key"].removesuffix("-SUB-01")
                self.assertIn(product, direct_contracts)
                result = requests.Response()
                result.status_code = 200
                result.url = url
                if url.endswith("/deployments"):
                    body = {"value": [{"name": model} for model in direct_contracts[product]["allowed_models"]]}
                elif kwargs["json"]["model"] == "validation-denied-model":
                    result.status_code = 403
                    body = {"error": {"code": "unauthorized_model_access"}}
                else:
                    body = {"choices": [{"message": {"content": "Hello"}}]}
                result._content = json.dumps(body).encode()
                return result

            consumption = next(source for source in cells("access-contracts")
                               if "deployed_policy = " in source)
            with patch("requests.get", side_effect=request) as get, patch("requests.post", side_effect=request) as post:
                exec(consumption, namespace)
            self.assertEqual(get.call_count, 2)
            self.assertEqual(post.call_count, 4)
            self.assertEqual(apim.client.product_policy.get.call_count, 3)
            for call in apim.client.product_policy.get.call_args_list:
                self.assertEqual(call.kwargs.get("policy_id"), "policy")
            namespace["probe_requests"] = 1
            capacity = next(source for source in cells("access-contracts") if "capacity_rows = []" in source)
            namespace["display"] = lambda *args: None
            with patch("requests.post", side_effect=request) as post, patch("matplotlib.pyplot.show"):
                exec(capacity, namespace)
            self.assertEqual(post.call_count, 2)
            results = namespace["run"].results
            for case in ("grants", "consume", "rbac", "capacity"):
                self.assertTrue(any(result.case == f"{case}:{foundry_product}" and result.status == "SKIP"
                                    for result in results))
            self.assertTrue(any(result.case == f"foundry-auth-policy:{foundry_product}" and result.status == "PASS"
                                for result in results))
            self.assertFalse(any(result.status in ("FAIL", "BLOCKED") for result in results))
            namespace["run"].finish()


if __name__ == "__main__":
    unittest.main()
