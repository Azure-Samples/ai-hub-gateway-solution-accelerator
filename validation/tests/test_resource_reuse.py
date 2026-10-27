"""Offline regressions for stable validation identities and safe resource reuse."""

import ast
import contextlib
import io
import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from azure.ai.projects.models import PromptAgentDefinition
from azure.core.exceptions import HttpResponseError, ResourceNotFoundError

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))
import consumerhelpers
import foundrychat
from contracttools import scoped_deployment_name


class ScopedDeploymentNameTests(unittest.TestCase):
    def test_name_is_stable_case_insensitive_and_scoped_to_the_gateway(self):
        first = scoped_deployment_name("validation-alerts", "/subscriptions/sub/service/gateway")
        self.assertEqual(first, scoped_deployment_name(
            "validation-alerts", "/SUBSCRIPTIONS/SUB/SERVICE/GATEWAY/",
        ))
        self.assertNotEqual(first, scoped_deployment_name(
            "validation-alerts", "/subscriptions/sub/service/another-gateway",
        ))

    def test_deployment_names_stay_within_azures_length_limit(self):
        self.assertEqual(len(scoped_deployment_name("x" * 100, "/gateway")), 64)
        self.assertNotEqual(scoped_deployment_name("x" * 100, "/gateway"),
                            scoped_deployment_name("x" * 99 + "y", "/gateway"))


class StableNotebookIdentityTests(unittest.TestCase):
    def test_asset_names_and_deployment_names_do_not_depend_on_run_id(self):
        fields = {"name", "use_case_name", "useCaseName", "apikey_secret", "agent_name", "namePrefix"}
        variables = {"contract_use_case_name", "alert_prefix", "publish_deployment_name", "use_case_name"}
        violations = []
        for path in (ROOT / "validation").glob("*.ipynb"):
            for index, cell in enumerate(json.loads(path.read_text(encoding="utf-8"))["cells"]):
                if cell["cell_type"] != "code":
                    continue
                for node in ast.walk(ast.parse("".join(cell["source"]))):
                    expressions = []
                    if isinstance(node, ast.Dict):
                        expressions.extend(value for key, value in zip(node.keys, node.values)
                                           if isinstance(key, ast.Constant) and key.value in fields)
                    elif isinstance(node, ast.Assign):
                        if any(isinstance(target, ast.Name) and target.id in variables
                               for target in node.targets):
                            expressions.append(node.value)
                        if any(isinstance(target, ast.Tuple) and any(
                            isinstance(item, ast.Name) and item.id == "use_case"
                            for item in target.elts
                        ) for target in node.targets):
                            expressions.append(node.value)
                    elif isinstance(node, ast.Call):
                        if isinstance(node.func, ast.Name) and node.func.id == "deploy_contract":
                            expressions.extend(node.args[2:3])
                        elif isinstance(node.func, ast.Attribute) and node.func.attr == "deploy":
                            expressions.extend(node.args[1:2])
                        expressions.extend(keyword.value for keyword in node.keywords
                                           if keyword.arg == "agent_name")
                    for expression in expressions:
                        if any(isinstance(part, ast.Name) and part.id in {"run_id", "timestamp"}
                               for part in ast.walk(expression)):
                            violations.append(f"{path.name}: cell {index}: {ast.unparse(expression)}")
        self.assertEqual(violations, [], "\n".join(violations))


class ProductReuseTests(unittest.TestCase):
    def setUp(self):
        self.context = SimpleNamespace(config={"resource_group": "fixture-rg"})
        self.apim = Mock(apim_resource_name="fixture-apim", apim_service_id=(
            "/subscriptions/sub/resourceGroups/fixture-rg/providers/"
            "Microsoft.ApiManagement/service/fixture-apim"
        ))
        self.product_id = "LLM-Ops-AlertProbe-DEV"
        self.product_resource_id = f"{self.apim.apim_service_id}/products/{self.product_id}"

    def test_existing_product_detection_is_case_insensitive_and_exact(self):
        self.apim.client.product.list_by_service.return_value = [
            SimpleNamespace(name=self.product_id.upper()),
        ]
        self.assertTrue(consumerhelpers.product_exists(self.context, self.apim, self.product_id))
        self.assertFalse(consumerhelpers.product_exists(self.context, self.apim, self.product_id + "-other"))

    def test_reused_or_unrecorded_product_is_not_deleted(self):
        artifact = Mock()
        artifact.cleanup_candidates.return_value = []
        with contextlib.redirect_stdout(io.StringIO()), patch.object(consumerhelpers, "cli_json") as cli:
            consumerhelpers.delete_owned_product(
                self.context, self.apim, self.product_id, artifact=artifact,
            )
        cli.assert_not_called()

    def test_only_a_positively_recorded_new_product_can_be_deleted(self):
        artifact = Mock()
        artifact.cleanup_candidates.return_value = [self.product_resource_id.upper()]
        with patch.object(consumerhelpers, "cli_json") as cli:
            consumerhelpers.delete_owned_product(
                self.context, self.apim, self.product_id, artifact=artifact,
            )
        self.assertEqual(cli.call_args.args[0:3], ("apim", "product", "delete"))
        self.assertIn(self.product_id, cli.call_args.args)

    def test_inventory_permission_error_is_not_treated_as_a_missing_product(self):
        self.apim.client.product.list_by_service.side_effect = HttpResponseError("Forbidden")
        with self.assertRaises(HttpResponseError):
            consumerhelpers.product_exists(self.context, self.apim, self.product_id)


class PilotProductRerunTests(unittest.TestCase):
    def test_repeated_pilot_deployments_preserve_product_identity_and_do_not_own_reused_products(self):
        import utils
        from validationtools import ValidationRun

        for filename in ("llm-backend-onboarding-runner.ipynb", "citadel-universal-llm-api-all-models-tests.ipynb"):
            with self.subTest(notebook=filename):
                source = ["".join(cell["source"]) for cell in json.loads(
                    (ROOT / "validation" / filename).read_text(encoding="utf-8")
                )["cells"] if cell["cell_type"] == "code"]
                deploy_cell = next(text for text in source if "owned_product_id = None" in text)
                cleanup_cell = next(text for text in source if "product_id != owned_product_id" in text)
                products = {}
                apim = Mock(apim_resource_name="gateway", apim_service_id="/subscriptions/sub/service/gateway")
                apim.client.product.list_by_service.side_effect = lambda *args: [
                    SimpleNamespace(name=key.upper()) for key in products
                ]
                deployments = []
                for run_id in ("first-run", "second-run"):
                    namespace = {
                        "utils": utils, "run": ValidationRun("pilot-rerun"), "run_id": run_id,
                        "context": SimpleNamespace(config={"resource_group": "rg"}), "apim": apim,
                        "product_id": "LLM-Validation-Pilot-DEV", "access_params": Path("fixture.bicepparam"),
                        "scenario": "pilot", "location": "region", "cleanup_enabled": True,
                        "product_exists": consumerhelpers.product_exists,
                        "scoped_deployment_name": scoped_deployment_name,
                    }

                    def deploy(path, location, name):
                        deployments.append(name)
                        product_id = namespace["product_id"]
                        products[product_id] = {"name": product_id}
                        return {"endpoints": {"value": [{
                            "productId": product_id, "subscriptionName": product_id + "-SUB-01",
                        }]}}

                    namespace["deploy_contract"] = deploy
                    with contextlib.redirect_stdout(io.StringIO()):
                        exec(deploy_cell, namespace)
                        if run_id == "second-run":
                            self.assertIsNone(namespace["owned_product_id"])
                            exec(cleanup_cell, namespace)
                        else:
                            self.assertEqual(namespace["owned_product_id"], namespace["product_id"])
                self.assertEqual(len(products), 1)
                self.assertEqual(deployments[0], deployments[1])
                apim.client.product.delete.assert_not_called()


class FoundryAgentReuseTests(unittest.TestCase):
    def setUp(self):
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)
        self.project = Mock()
        self.definition = PromptAgentDefinition(model="hub-connection/chat", instructions="HR assistance")
        self.agent = SimpleNamespace(
            name="HR-ChatAgent", version="1", definition=self.definition, metadata={},
        )
        self.project.agents.get.return_value = SimpleNamespace(
            versions=SimpleNamespace(latest=self.agent),
        )

    def test_unchanged_definition_reuses_the_existing_agent_version(self):
        agent, created = foundrychat.ensure_agent_version(self.project, "HR-ChatAgent", self.definition)
        self.assertIs(agent, self.agent)
        self.assertFalse(created)
        self.project.agents.create_version.assert_not_called()

    def test_missing_agent_is_created_once_and_next_run_reuses_its_version(self):
        self.project.agents.get.side_effect = [
            ResourceNotFoundError("Missing"),
            SimpleNamespace(versions=SimpleNamespace(latest=self.agent)),
        ]
        self.project.agents.create_version.return_value = self.agent
        first, first_created = foundrychat.ensure_agent_version(
            self.project, "HR-ChatAgent", self.definition,
        )
        second, second_created = foundrychat.ensure_agent_version(
            self.project, "HR-ChatAgent", self.definition,
        )
        self.assertIs(first, second)
        self.assertTrue(first_created)
        self.assertFalse(second_created)
        self.project.agents.create_version.assert_called_once()
        self.assertEqual(self.project.agents.create_version.call_args.kwargs["agent_name"], "HR-ChatAgent")

    def test_changed_definition_creates_a_version_under_the_same_name(self):
        self.project.agents.create_version.return_value = SimpleNamespace(name="HR-ChatAgent", version="2")
        changed = PromptAgentDefinition(model="hub-connection/chat", instructions="Updated HR assistance")
        agent, created = foundrychat.ensure_agent_version(self.project, "HR-ChatAgent", changed)
        self.assertEqual(agent.version, "2")
        self.assertTrue(created)
        self.project.agents.create_version.assert_called_once()
        self.assertEqual(self.project.agents.create_version.call_args.kwargs["agent_name"], "HR-ChatAgent")

    def test_server_added_defaults_do_not_create_another_version_on_rerun(self):
        self.project.agents.get.side_effect = ResourceNotFoundError("Missing")
        self.project.agents.create_version.return_value = self.agent
        foundrychat.ensure_agent_version(self.project, "HR-ChatAgent", self.definition)
        self.agent.metadata = self.project.agents.create_version.call_args.kwargs["metadata"]
        self.agent.definition = PromptAgentDefinition(
            model="hub-connection/chat", instructions="HR assistance", tools=[], tool_choice="auto",
        )
        self.project.agents.get.side_effect = None
        agent, created = foundrychat.ensure_agent_version(self.project, "HR-ChatAgent", self.definition)
        self.assertIs(agent, self.agent)
        self.assertFalse(created)
        self.assertEqual(self.project.agents.create_version.call_count, 1)

    def test_lookup_errors_propagate_without_attempting_creation(self):
        self.project.agents.get.side_effect = HttpResponseError("Forbidden")
        with self.assertRaises(HttpResponseError):
            foundrychat.ensure_agent_version(self.project, "HR-ChatAgent", self.definition)
        self.project.agents.create_version.assert_not_called()


class AlertingRerunTests(unittest.TestCase):
    def test_two_runs_update_the_same_assets_with_fresh_probe_counters_and_safe_cleanup(self):
        import test_alerting_defaults as alerting_tests
        from test_external_defaults import cells, execute
        from xml.etree import ElementTree as ET

        products, resources = {}, {}
        deployment_names, counters = [], []
        artifacts = []
        code = cells("alerting")

        def artifact(label):
            result = Mock(params_file=Path(label + ".bicepparam"))
            owned = {}
            result.record_resource.side_effect = lambda identifier, *, created: owned.update(
                {identifier: owned.get(identifier, True) and created},
            )
            result.cleanup_candidates.side_effect = lambda: [key for key, created in owned.items() if created]
            return result

        for run_id in ("first-run", "second-run"):
            namespace = alerting_tests.AlertingDefaultsTests().initialize()
            namespace["run_id"] = run_id
            apim = namespace["apim"]
            apim.client.product.list_by_service.side_effect = lambda *args: [
                SimpleNamespace(name=key) for key in products
            ]
            access, alerts = artifact("access"), artifact("alerts")
            artifacts.append((access, alerts))
            namespace["access_artifact"] = Mock(return_value=access)
            namespace["prepare_artifact"] = Mock(return_value=alerts)

            def deploy(path, location, name):
                deployment_names.append(name)
                product_id = namespace["product_id"]
                if path == access.params_file:
                    products[product_id] = namespace["policy_xml"]
                    return {
                        "products": {"value": [{"productId": product_id}]},
                        "subscriptions": {"value": [{"productId": product_id, "name": product_id + "-SUB-01"}]},
                    }
                prefix = namespace["alert_prefix"]
                base = (f"/subscriptions/{namespace['context'].config['subscription_id']}"
                        f"/resourceGroups/{namespace['context'].config['resource_group']}/providers/Microsoft.Insights")
                names = [f"{prefix}-{item['name']}-alert" for item in namespace["alert_definitions"]]
                for name in names:
                    identifier = f"{base}/scheduledQueryRules/{name}"
                    resources[identifier] = {
                        "id": identifier, "enabled": True, "product": namespace["product_display_name"],
                        "scopes": [namespace["app_insights_id"]],
                    }
                action_group = f"{base}/actionGroups/{prefix}-alerts-ag"
                resources[action_group] = {"id": action_group}
                return {"alertRuleNames": {"value": names}, "actionGroupId": {"value": action_group}}

            def cli(*args):
                if args[:2] == ("resource", "list"):
                    return [identifier.upper() for identifier in resources]
                if args[:3] == ("monitor", "scheduled-query", "show"):
                    return next(value for key, value in resources.items() if key.endswith("/" + args[-1]))
                raise AssertionError(f"Unexpected Azure CLI operation: {args[:3]}")

            namespace["deploy_contract"] = Mock(side_effect=deploy)
            namespace["cli_json"] = Mock(side_effect=cli)
            with contextlib.redirect_stdout(io.StringIO()):
                for marker in ('use_case = {', 'outputs = deploy_contract(contract_artifact',
                               'alert_prefix =', 'alert_outputs = deploy_contract'):
                    execute(next(source for source in code if marker in source), namespace)
                counters.append(ET.fromstring(namespace["policy_xml"]).find(".//llm-token-limit").get("counter-key"))
                namespace["cleanup_enabled"] = True
                if run_id == "second-run":
                    with patch.object(consumerhelpers, "cli_json") as deletes:
                        execute(code[-1], namespace)
                    deletes.assert_not_called()
            self.assertEqual(len(products), 1)
            self.assertEqual(len(resources), 3)

        self.assertEqual(set(products), {"LLM-Ops-AlertProbe-DEV"})
        self.assertEqual(deployment_names[:2], deployment_names[2:])
        self.assertNotEqual(counters[0], counters[1])
        self.assertIn("first-run", counters[0])
        self.assertIn("second-run", counters[1])
        self.assertEqual(len(artifacts[0][0].cleanup_candidates()), 1)
        self.assertEqual(len(artifacts[0][1].cleanup_candidates()), 3)
        self.assertEqual(artifacts[1][0].cleanup_candidates(), [])
        self.assertEqual(artifacts[1][1].cleanup_candidates(), [])


if __name__ == "__main__":
    unittest.main()
