import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from apimtools import APIMClientTool


class APIMContextTests(unittest.TestCase):
    @patch("apimtools.DefaultAzureCredential")
    @patch("apimtools.ApiManagementClient")
    def test_context_does_not_enumerate_secrets(self, factory, credential):
        factory.return_value.api_management_service.get.return_value = SimpleNamespace(
            id="service-id", gateway_url="https://gateway/"
        )
        tool = APIMClientTool("rg", "apim").initialize_context({
            "id": "sub", "tenantId": "tenant", "user": {"name": "user"}
        })
        self.assertEqual(tool.apim_resource_gateway_url, "https://gateway")
        factory.return_value.subscription.list.assert_not_called()
        factory.return_value.subscription.list_secrets.assert_not_called()

    def test_exact_discovery_is_not_substring_or_mutable(self):
        tool = APIMClientTool("rg", "apim")
        tool.client = Mock()
        tool.apim_resource_gateway_url = "https://gateway"
        tool.client.api.list_by_service.return_value = [
            SimpleNamespace(path="models-extra", id="wrong", name="wrong"),
            SimpleNamespace(path="models", id="right", name="right"),
        ]
        self.assertEqual(tool.discover_api_exact("models")["id"], "right")
        self.assertIsNone(tool.azure_endpoint)
        with self.assertRaises(RuntimeError):
            tool.discover_api_exact("missing")

    def test_key_is_targeted_and_required(self):
        tool = APIMClientTool("rg", "apim")
        tool.client = Mock()
        tool.client.subscription.list_secrets.return_value.primary_key = "secret"
        self.assertEqual(tool.get_subscription_key("exact"), "secret")
        tool.client.subscription.list_secrets.assert_called_once_with("rg", "apim", "exact")
        tool.client.subscription.list_secrets.return_value.primary_key = None
        with self.assertRaises(RuntimeError):
            tool.get_subscription_key("exact")


if __name__ == "__main__":
    unittest.main()
