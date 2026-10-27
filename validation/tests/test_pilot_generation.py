import contextlib
import io
import json
import sys
import shutil
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))

from contracttools import access_policy, compile_parameters, write_parameters
import utils


class PilotGenerationTests(unittest.TestCase):
    def test_actual_pilot_parameter_cells(self):
        """Exercise the visible parameter cells, not a separately maintained proxy."""
        for name in ("llm-backend-onboarding-runner", "citadel-access-contracts-tests",
                     "citadel-universal-llm-api-all-models-tests"):
            notebook = json.loads((ROOT / "validation" / (name + ".ipynb")).read_text(encoding="utf-8"))
            with self.subTest(notebook=name), tempfile.TemporaryDirectory() as temporary:
                coordinates = {"subscriptionId": "00000000-0000-0000-0000-000000000001",
                               "resourceGroupName": "fixture-rg", "name": "fixture-apim"}
                context = SimpleNamespace(
                    config={"subscription_id": coordinates["subscriptionId"], "resource_group": "fixture-rg"},
                    account={"tenantId": coordinates["subscriptionId"]},
                )
                apim = Mock()
                apim.get_managed_identity_info.return_value = {"name": "fixture-mi", "resourceGroup": "fixture-rg"}
                namespace = {
                    "root": ROOT, "run_dir": Path(temporary), "run_id": "fixture",
                    "scenario": "fixture", "apim_coordinates": coordinates, "context": context,
                    "apim": apim, "complete_backend_configuration": True, "model_aliases": [],
                    "llm_backends_config": [{"backendId": "fixture-backend", "backendType": "ai-foundry",
                        "endpoint": "https://fixture.services.ai.azure.com", "authType": "managed-identity",
                        "supportedModels": [{"name": "future-model", "modelFormat": "OpenAI"}]}],
                    "use_keyvault_integration": False, "use_foundry_integration": False,
                    "chat_models": ["future-model"], "model": "future-model",
                    "keyvault": coordinates, "foundry": {}, "json": json,
                    "access_policy": access_policy, "write_parameters": write_parameters,
                    "utils": utils,
                }
                for cell in notebook["cells"]:
                    source = "".join(cell["source"])
                    if cell["cell_type"] != "code":
                        continue
                    if "access_contracts = [" in source or (
                        "write_parameters(" in source and "from contracttools" not in source
                    ):
                        with contextlib.redirect_stdout(io.StringIO()):
                            exec(compile(source, name, "exec"), namespace)
                files = list(Path(temporary).rglob("*.bicepparam"))
                self.assertTrue(files, "Notebook must generate actual .bicepparam files")
                for file in files:
                    text = file.read_text(encoding="utf-8")
                    self.assertIn("using ", text)
                    self.assertIn("param apim", text)
                    self.assertNotIn("REPLACE", text)

    @unittest.skipUnless(shutil.which("az"), "Azure CLI required for offline Bicep compilation")
    def test_real_access_contract_template_compiles(self):
        with tempfile.TemporaryDirectory() as temporary:
            coordinates = {"subscriptionId": "00000000-0000-0000-0000-000000000001",
                           "resourceGroupName": "fixture-rg", "name": "fixture-apim"}
            path = write_parameters(
                ROOT / "bicep" / "infra" / "citadel-access-contracts" / "main.bicep",
                {"apim": coordinates, "keyVault": coordinates, "useTargetAzureKeyVault": False,
                 "useCase": {"businessUnit": "Test", "useCaseName": "Fixture", "environment": "DEV"},
                 "apiNameMapping": {"LLM": ["universal-llm-api"]},
                 "services": [{"code": "LLM", "apiKeySecretName": "fixture-key",
                               "policyXml": access_policy(["future-model"], 100, 1000, "Hourly")}]},
                Path(temporary),
            )
            compiled = compile_parameters(path)
            parameters = json.loads(compiled["parametersJson"])["parameters"]
            self.assertEqual(parameters["apim"]["value"], coordinates)


if __name__ == "__main__":
    unittest.main()
