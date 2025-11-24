import os, sys, json, requests
sys.path.insert(1, '../shared')  # add the shared directory to the Python path
import utils
from azure.identity import DefaultAzureCredential
from azure.mgmt.apimanagement import ApiManagementClient
from azure.mgmt.apimanagement.models import SubscriptionKeysContract 

class APIMClientTool:
    def __init__(self, resource_group_name, apim_resource_name = ""):
        self.resource_group_name = resource_group_name
        self.apim_resource_name = apim_resource_name
        self.azure_endpoint: str = None

    def initialize(self):
        output = utils.run("az account show", "Retrieved az account", "Failed to get the current az account")
        if output.success and output.json_data:
            self.current_user = output.json_data['user']['name']
            self.tenant_id = output.json_data['tenantId']
            self.subscription_id = output.json_data['id']
            utils.print_info(f"Current user: {self.current_user}")
            utils.print_info(f"Tenant ID: {self.tenant_id}")
            utils.print_info(f"Subscription ID: {self.subscription_id}")

            if not self.apim_resource_name:
                output = utils.run(f"az resource list -g {self.resource_group_name} --resource-type Microsoft.ApiManagement/service", "Listing APIM Resources", "Failed to list APIM resources")
                if output.success and output.json_data and len(output.json_data) > 0:
                    self.apim_resource_name = output.json_data[0]['name']
                else:
                    raise Exception(f"APIM resource not found in resource group {self.resource_group_name}.")

            self.client = ApiManagementClient(credential=DefaultAzureCredential(), subscription_id=self.subscription_id)

            api_management_service = self.client.api_management_service.get(self.resource_group_name, self.apim_resource_name)

            self.apim_service_id = api_management_service.id
            utils.print_info(f"APIM Service Id: {self.apim_service_id}")

            self.apim_resource_gateway_url: str = api_management_service.gateway_url
            utils.print_info(f"APIM Gateway URL: {self.apim_resource_gateway_url}")
            self.apim_subscriptions = []
            subscriptions = self.client.subscription.list(self.resource_group_name, self.apim_resource_name)
            for subscription in subscriptions:
                subscription_secrets = self.client.subscription.list_secrets(self.resource_group_name, self.apim_resource_name, str(subscription.name))
                self.apim_subscriptions.append({ "name": subscription.name, "key": subscription_secrets.primary_key})
                utils.print_info(f"Retrieved key {len(self.apim_subscriptions) - 1} for subscription: {subscription.name}")

    def discover_api(self, api_path_filter = "/openai"):
        api_management_service = self.client.api_management_service.get(self.resource_group_name, self.apim_resource_name)
        apis = self.client.api.list_by_service(self.resource_group_name, self.apim_resource_name)
        api_path = None
        for api in apis:
            if api_path_filter in api.path:
                api_path = api.path
                self.api_id = api.id
                utils.print_info(f"Found API with id {self.api_id} and path {api_path}")
                self.azure_endpoint = f"{self.apim_resource_gateway_url}/{api_path.replace(api_path_filter, "")}"
                utils.print_info(f"Azure Endpoint with APIM {self.azure_endpoint}")
                break
        if not api_path:
            raise Exception(f"API with path filter `{api_path_filter}` not found.")

    def get_debug_credentials(self, expire_after) -> str | None:
        request = {
            "credentialsExpireAfter": expire_after,
            "apiId": f"{self.apim_service_id}/apis/{self.api_id}",
            "purposes": ["tracing"]
        }
        output = utils.run(f"az rest --method post --uri {self.apim_service_id}/gateways/managed/listDebugCredentials?api-version=2023-05-01-preview --body \"{str(request)}\"",
                "Retrieved APIM debug credentials", "Failed to get the APIM debug credentials")
        return output.json_data['token'] if output.success and output.json_data else None
         
    def get_trace(self, trace_id) -> str | None:
        request = {
            "traceId": trace_id
        }
        output = utils.run(f"az rest --method post --uri {self.apim_service_id}/gateways/managed/listTrace?api-version=2023-05-01-preview --body \"{str(request)}\"",
                "Retrieved trace details", "Failed to get the trace details")
        return output.json_data if output.success and output.json_data else None

    def get_policy_fragment_supported_models(self, fragment_name: str = "set-backend-pools", debug: bool = False) -> list[str]:
        """
        Retrieves a policy fragment from APIM and extracts the list of supported model names.
        
        Args:
            fragment_name: Name of the policy fragment (default: "set-backend-pools")
            debug: If True, prints the raw policy XML for debugging (default: False)
            
        Returns:
            List of unique supported model names extracted from the policy fragment
            
        Raises:
            RuntimeError: If the policy fragment cannot be retrieved or parsed
        """
        try:
            # Get the policy fragment using Azure SDK
            policy_fragment = self.client.policy_fragment.get(
                resource_group_name=self.resource_group_name,
                service_name=self.apim_resource_name,
                id=fragment_name
            )
            
            # Extract the XML policy content
            policy_xml = policy_fragment.value
            utils.print_info(f"Retrieved policy fragment: {fragment_name}")
            
            if debug:
                utils.print_info("=" * 80)
                utils.print_info("RAW POLICY XML:")
                utils.print_info("=" * 80)
                print(policy_xml)
                utils.print_info("=" * 80)
            
            # Parse the XML to extract supported models
            supported_models = self._extract_supported_models_from_policy(policy_xml)
            
            utils.print_info(f"Found {len(supported_models)} unique supported models")
            return supported_models
            
        except Exception as e:
            raise RuntimeError(f"Failed to retrieve or parse policy fragment '{fragment_name}': {str(e)}") from e
    
    def _extract_supported_models_from_policy(self, policy_xml: str) -> list[str]:
        """
        Extracts supported model names from the policy XML content.
        
        Args:
            policy_xml: The XML content of the policy fragment
            
        Returns:
            List of unique model names found in supportedModels arrays
        """
        import re
        import html
        
        supported_models = set()
        
        # Decode HTML entities if present (e.g., &quot; -> ")
        decoded_xml = html.unescape(policy_xml)
        
        # Multiple patterns to handle different formatting styles
        patterns = [
            # Pattern 1: Standard format with quotes
            r'"supportedModels"\s*,\s*new\s+JArray\s*\((.*?)\)',
            # Pattern 2: With escaped quotes
            r'&quot;supportedModels&quot;\s*,\s*new\s+JArray\s*\((.*?)\)',
            # Pattern 3: More flexible whitespace and line breaks
            r'supportedModels["\s]*,\s*new\s+JArray\s*\((.*?)\)',
        ]
        
        for pattern in patterns:
            matches = re.findall(pattern, decoded_xml, re.DOTALL | re.IGNORECASE)
            
            for match in matches:
                # Extract individual model names from the JArray
                # Handle both regular quotes and escaped quotes
                model_patterns = [
                    r'"([^"]+)"',           # Regular quotes
                    r'&quot;([^&]+)&quot;', # HTML escaped quotes
                ]
                
                for model_pattern in model_patterns:
                    models = re.findall(model_pattern, match)
                    # Filter out non-model strings (like "supportedModels" itself)
                    models = [m for m in models if m and m != 'supportedModels']
                    supported_models.update(models)
        
        # If still no models found, log a warning
        if not supported_models:
            utils.print_warning("No supported models found in policy fragment. Check if the policy format matches expected pattern.")
        
        # Convert set to sorted list for consistent output
        return sorted(list(supported_models))

