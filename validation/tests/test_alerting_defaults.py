"""Offline regressions for optional alert email and GPT-only probe selection."""
import contextlib
import io
import json
import re
import sys
import shutil
import tempfile
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared"))
import validationtools
import consumerhelpers
from contracttools import compile_parameters, write_parameters
from test_external_defaults import apim_fixture, cells, execute, snapshot


class AlertingDefaultsTests(unittest.TestCase):
    def test_configuration_refreshes_a_cached_consumer_module_missing_new_helpers(self):
        cached = ModuleType("consumerhelpers")
        cached.__dict__.update(vars(consumerhelpers))
        cached.__dict__.pop("product_exists")
        namespace = {}
        with patch.dict(sys.modules, {"consumerhelpers": cached}), \
                contextlib.redirect_stdout(io.StringIO()):
            execute(cells("alerting")[0], namespace)
        self.assertTrue(callable(namespace["product_exists"]))
        self.assertIs(namespace["product_exists"], cached.product_exists)
        self.assertEqual(cached.__file__, consumerhelpers.__file__)

    def test_configuration_surfaces_helper_reload_failures(self):
        with patch("importlib.reload", side_effect=RuntimeError("Helper refresh failed")), \
                contextlib.redirect_stdout(io.StringIO()), \
                self.assertRaisesRegex(RuntimeError, "Helper refresh failed"):
            execute(cells("alerting")[0], {})

    def initialize(self, *, email=None, model_override=None, skip=None, models=None, discover=False,
                   saved_email=None):
        namespace = {}
        values = snapshot()
        values.pop("VALIDATION_ALERT_EMAIL", None)
        values.pop("ALERT_EMAIL_ADDRESS", None)
        if saved_email is not None:
            values["VALIDATION_ALERT_EMAIL"] = saved_email
        values["LLM_BACKEND_CONFIG"] = json.dumps([{
            "backendId": "fixture", "backendType": "ai-foundry",
            "supportedModels": [{"name": name} for name in (
                models if models is not None else
                ["Mistral-chat", "gpt-image-example", "GPT-MINI-chat", "gPt-primary-chat", "text-vector"]
            )],
        }])
        if discover:
            values.pop("APIM_APP_INSIGHTS_NAME")
        with contextlib.redirect_stdout(io.StringIO()), patch.object(Path, "mkdir"):
            execute(cells("alerting")[0], namespace)
            namespace.update(alert_email_address=email, model_override=model_override, skipped_models=skip)
            apim = apim_fixture()
            namespace["APIMClientTool"] = Mock(return_value=apim)
            namespace["cli_json"] = Mock(return_value=[
                "/subscriptions/fixture-sub/resourceGroups/fixture-rg/providers/"
                "Microsoft.Insights/components/logger-component"
            ])
            with patch.object(validationtools, "_run_json", side_effect=[
                values, {"id": "fixture-sub", "tenantId": "fixture-tenant"},
            ]), patch.object(consumerhelpers, "cli_json", return_value={"value": [
                "/subscriptions/fixture-sub/resourceGroups/fixture-rg/providers/"
                "Microsoft.Insights/components/logger-component"
            ]}) as discovery:
                execute(cells("alerting")[1], namespace)
            namespace["_logger_discovery"] = discovery
        return namespace

    def test_default_azd_run_has_no_email_and_selects_gpt_not_image_or_non_gpt(self):
        namespace = self.initialize()
        self.assertEqual(namespace["alert_email_address"], "")
        self.assertEqual(namespace["model_name"], "gPt-primary-chat")
        self.assertEqual(namespace["app_insights_name"], "actual-gateway-telemetry")

    def test_skip_keywords_are_case_insensitive_and_apply_before_gpt_selection(self):
        namespace = self.initialize(skip=["PRIMARY"])
        self.assertEqual(namespace["model_name"], "GPT-MINI-chat")
        with self.assertRaisesRegex(ValueError, "GPT|gpt"):
            self.initialize(skip=["GPT"])

    def test_explicit_model_override_cannot_bypass_gpt_or_image_rules(self):
        for model in ("Mistral-chat", "gpt-image-example"):
            with self.subTest(model=model), self.assertRaisesRegex(ValueError, "GPT|gpt"):
                self.initialize(model_override=model)
        namespace = self.initialize(model_override="GPT-MINI-chat", skip=[])
        self.assertEqual(namespace["model_name"], "GPT-MINI-chat")

    def test_no_eligible_model_reports_an_actionable_error(self):
        with self.assertRaisesRegex(ValueError, "GPT|gpt"):
            self.initialize(models=["gpt-image-example", "Mistral-chat", "text-vector"])

    def test_email_is_optional_but_supplied_invalid_email_still_fails(self):
        namespace = self.initialize(email="operator@example.com")
        self.assertEqual(namespace["alert_email_address"], "operator@example.com")
        for email in ("REPLACE@example.com", "not-an-address"):
            with self.subTest(email=email), self.assertRaisesRegex(ValueError, "email|inbox"):
                self.initialize(email=email)

    def test_email_free_run_can_discover_component_from_exact_apim_logger(self):
        namespace = self.initialize(discover=True)
        self.assertEqual(namespace["app_insights_name"], "logger-component")
        self.assertEqual(namespace["alert_email_address"], "")
        namespace["_logger_discovery"].assert_called_once()
        self.assertEqual(namespace["_logger_discovery"].call_args.args[:3], ("rest", "--method", "get"))
        namespace["cli_json"].assert_not_called()

    def test_alert_parameter_generation_has_no_email_receiver_when_not_supplied(self):
        for email in (None, "operator@example.com"):
            with self.subTest(email=email):
                namespace = self.initialize(email=email)
                namespace["product_display_name"] = "LLM Ops Fixture DEV"
                namespace["prepare_artifact"] = Mock(return_value=SimpleNamespace(
                    preview=lambda: "parameter preview",
                ))
                source = next(source for source in cells("alerting") if "alert_parameters = {" in source)
                with contextlib.redirect_stdout(io.StringIO()):
                    execute(source, namespace)
                parameters = namespace["prepare_artifact"].call_args.args[1]
                self.assertEqual(parameters["alertEmailAddress"], email or "")
                self.assertEqual(len(parameters["alerts"]), 2)
                self.assertIs(parameters["alertsEnabled"], True)

    def test_explicit_empty_email_overrides_a_saved_azd_recipient(self):
        namespace = self.initialize(email="", saved_email="saved@example.com")
        self.assertEqual(namespace["alert_email_address"], "")
        namespace = self.initialize(saved_email="saved@example.com")
        self.assertEqual(namespace["alert_email_address"], "saved@example.com")

    def test_email_free_summary_skips_delivery_without_disabling_other_validation(self):
        namespace = self.initialize()
        namespace.update(verify_alert_firing=False, notification_evidence="unused supplied receipt")
        namespace["run"].check("enforcement-fixture", True)
        summary = next(source for source in cells("alerting") if "notification-delivery" in source)
        with contextlib.redirect_stdout(io.StringIO()):
            execute(summary, namespace)
        result = next(result for result in namespace["run"].results if result.case == "notification-delivery")
        self.assertEqual(result.status, "SKIP")
        self.assertIn("disabled", result.reason)
        self.assertFalse(any(result.status in ("FAIL", "BLOCKED") for result in namespace["run"].results))

    @unittest.skipUnless(shutil.which("az"), "Local Azure CLI/Bicep compiler required")
    def test_actual_alert_template_compiles_without_an_email_parameter(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            parameters = {
                "appInsights": {"subscriptionId": "11111111-1111-1111-1111-111111111111",
                                "resourceGroupName": "fixture-rg", "name": "fixture-insights"},
                "namePrefix": "validation-alert-20261026175839-b739fe",
            }
            path = write_parameters(ROOT / "bicep" / "infra" / "app-insights-alert" / "main.bicep",
                                    parameters, Path(temporary))
            compiled = compile_parameters(path)
            template = json.loads(compiled["templateJson"])
            self.assertEqual(template["parameters"]["alertEmailAddress"]["defaultValue"], "")
            expression = template["variables"]["emailReceivers"]
            self.assertIn("if(not(empty(trim(parameters('alertEmailAddress'))))", expression)
            self.assertIn("createArray()", expression)
            self.assertIn("parameters('additionalEmailReceivers')", expression)
            self.assertNotIn("alertEmailAddress", json.loads(compiled["parametersJson"])["parameters"])
            self.assert_bounded_module_names(template)
            self.assertIn("parameters('namePrefix')", template["outputs"]["alertRuleNames"]["copy"]["input"])

    def assert_bounded_module_names(self, template):
        resources = template["resources"]
        resources = resources.values() if isinstance(resources, dict) else resources
        deployments = [resource for resource in resources
                       if resource["type"] == "Microsoft.Resources/deployments"]
        self.assertEqual(len(deployments), 3, "Action group plus log and metric deployment definitions")
        for deployment in deployments:
            expression = deployment["name"]
            match = re.fullmatch(r"\[format\('([^']*)', uniqueString\((.*)\)\)\]", expression)
            self.assertIsNotNone(match, "Nested deployment names must use one bounded deterministic hash, not the full prefix")
            literal = match.group(1)
            self.assertEqual(literal.count("{0}"), 1)
            # ARM uniqueString returns 13 characters regardless of prefix/suffix lengths.
            self.assertLessEqual(len(literal.replace("{0}", "x" * 13)), 64)
            self.assertIn("parameters('namePrefix')", match.group(2))


if __name__ == "__main__":
    unittest.main()
