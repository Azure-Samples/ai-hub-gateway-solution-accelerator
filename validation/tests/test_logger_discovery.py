"""APIM logger discovery uses ARM REST, not an unsupported CLI command group."""
import contextlib
import io
import json
import shutil
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
import consumerhelpers

COMPONENT = "/subscriptions/telemetry-sub/resourceGroups/telemetry-rg/providers/Microsoft.Insights/components/gateway-ai"


class LoggerDiscoveryTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("az"), "Local Azure CLI required for offline query evaluation")
    def test_projection_matches_real_arm_logger_shape_with_the_installed_cli(self):
        document = {"value": [
            {"name": "events", "properties": {"loggerType": "azureEventHub",
                                             "resourceId": "/eventhub", "credentials": {"key": "must-not-appear"}}},
            {"name": "insights", "properties": {"loggerType": "applicationInsights",
                                               "resourceId": COMPONENT,
                                               "credentials": {"instrumentationKey": "must-not-appear"}}},
        ]}
        original_cli = consumerhelpers.cli_json
        output = io.StringIO()

        def evaluate(*arguments):
            self.assertEqual(arguments[:3], ("rest", "--method", "get"))
            query = arguments[arguments.index("--query") + 1]
            return original_cli("version", "--query", "`" + json.dumps(document) + "` | " + query)

        with patch.object(consumerhelpers, "cli_json", side_effect=evaluate), contextlib.redirect_stdout(output):
            result = consumerhelpers.discover_apim_app_insights("sub", "rg", "apim")
        self.assertEqual(result["name"], "gateway-ai")
        self.assertNotIn("must-not-appear", output.getvalue())

    def test_supported_arm_request_uses_nested_logger_properties_and_no_credentials(self):
        with patch.object(consumerhelpers, "cli_json", return_value={"value": [COMPONENT]}) as cli:
            result = consumerhelpers.discover_apim_app_insights("sub", "gateway rg", "gateway")
        self.assertEqual(result, {
            "subscriptionId": "telemetry-sub", "resourceGroupName": "telemetry-rg", "name": "gateway-ai",
        })
        args = cli.call_args.args
        self.assertEqual(args[:3], ("rest", "--method", "get"))
        url = args[args.index("--url") + 1]
        self.assertIn("/subscriptions/sub/resourceGroups/gateway%20rg/", url)
        self.assertTrue(url.endswith("/service/gateway/loggers?api-version=2024-05-01"))
        query = args[args.index("--query") + 1]
        self.assertIn("properties.loggerType", query)
        self.assertIn("properties.resourceId", query)
        self.assertNotIn("credentials", query)

    def test_pagination_and_duplicate_resource_references_are_handled(self):
        next_url = "https://management.azure.com/next-page"
        with patch.object(consumerhelpers, "cli_json", side_effect=[
            {"value": [COMPONENT], "nextLink": next_url},
            {"value": [COMPONENT.upper()], "nextLink": None},
        ]) as cli:
            result = consumerhelpers.discover_apim_app_insights("sub", "rg", "apim")
        self.assertEqual(result["name"], "gateway-ai")
        self.assertEqual(cli.call_args.args[cli.call_args.args.index("--url") + 1], next_url)

    def test_missing_ambiguous_and_invalid_resource_ids_are_not_silently_chosen(self):
        for values in ([], [COMPONENT, COMPONENT + "-other"], [None], ["not-a-resource-id"]):
            with self.subTest(values=values), patch.object(
                consumerhelpers, "cli_json", return_value={"value": values}
            ), self.assertRaisesRegex(ValueError, "APIM_APP_INSIGHTS_NAME"):
                consumerhelpers.discover_apim_app_insights("sub", "rg", "apim")

    def test_malformed_pages_and_unsafe_next_links_fail_explicitly(self):
        for page in (None, [], {"value": None}, {"value": [], "nextLink": "https://untrusted.example/"}):
            with self.subTest(page=page), patch.object(consumerhelpers, "cli_json", return_value=page), \
                    self.assertRaises(ValueError):
                consumerhelpers.discover_apim_app_insights("sub", "rg", "apim")

    def test_cli_errors_propagate_instead_of_selecting_another_component(self):
        with patch.object(consumerhelpers, "cli_json", side_effect=RuntimeError("Permission denied")), \
                self.assertRaisesRegex(RuntimeError, "Permission denied"):
            consumerhelpers.discover_apim_app_insights("sub", "rg", "apim")

    def test_pagination_loop_stops_explicitly(self):
        url = ("https://management.azure.com/subscriptions/sub/resourceGroups/rg"
               "/providers/Microsoft.ApiManagement/service/apim/loggers?api-version=2024-05-01")
        with patch.object(consumerhelpers, "cli_json", return_value={"value": [COMPONENT], "nextLink": url}), \
                self.assertRaisesRegex(ValueError, "pagination loop"):
            consumerhelpers.discover_apim_app_insights("sub", "rg", "apim")


if __name__ == "__main__":
    unittest.main()
