## Primary components deployment

Below is a high-level guide to deploy the AI Hub Gateway Landing Zone main components.


### <a name="networking-components">Networking components</a>

For the AI Hub Gateway Landing Zone to be deployed, you will need to have/identify the following components:
- **Virtual network & subnet**: A virtual network to host the AI Hub Gateway Landing Zone.
    - APIM to be deployed in **internal mode** requires a subnet with /27 or larger with NSG that allows the critical rules.
    - **Private endpoints subnet(s)**: Private endpoints for the AI services to be exposed through the AI Hub Gateway Landing Zone. Usually a /27 or larger subnet would be sufficient.
- **Private DNS zone**: A private DNS zone to resolve the private endpoints.
    - Internal APIM relies on **private DNS** to resolve the APIM endpoints, so a Azure Private DNS zone or other DNS solution is required.
    - **Private endpoints DNS zone**: A private DNS zone to resolve the private endpoints for the connected Azure AI services.
- **ExpressRoute or VPN**: If you are planning to connect to on-premises or other clouds, you will need to have an ExpressRoute or VPN connection.
- **DMZ appliances**: If you are planning to expose backend and gateway services on the internet, you need to have a Web Application Firewall (like Azure Front Door & Application Gateway) and network firewall (like Azure Firewall) to govern both ingress and egress traffic.

### Azure API Management (APIM)
APIM is the central component of the AI Hub Gateway Landing Zone. 

Recommended deployment of APIM to be in **internal mode** to ensure that the gateway is not exposed to the internet and to ensure that the gateway is only accessible through the private network.

**internal mode** requires a subnet with /27 or larger with NSG that allows the critical rules in addition to management public IP (with DNS label set)

This is a great starting point to deploy APIM in internal mode: [Deploy Azure API Management in internal mode](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet?tabs=stv2)

### Application Insights
Application Insights is a critical component of the AI Hub Gateway Landing Zone, and it is used to monitor the operational performance of the gateway.

To deploy Application Insights, you can use the following guide: [How to integrate Azure API Management with Azure Application Insights](https://azure.github.io/apim-lab/apim-lab/6-analytics-monitoring/analytics-monitoring-6-2-application-insights.html) 

### Event Hub

Event Hub is used to stream usage and charge-back data to target data and charge back platforms.

To deploy Event Hub, you can use the following guide: [Logging with Event Hub](https://azure.github.io/apim-lab/apim-lab/6-analytics-monitoring/analytics-monitoring-6-3-event-hub.html)

### <a name="additional-components-deployment">Additional components deployment</a>

With the primary components deployed, you can now deploy or identify the AI services and backend services that will be exposed through the AI Hub Gateway.

Additional components may include:
- **Azure OpenAI**: You can have 1 or more OpenAI services deployed (like one with PTU and one with PAYG)
- **Azure AI Search**: Azure AI Search with indexed data (1 or more indexes)
- **Backend services**: Backend services that will include your AI business logic and experiences (like a python chat app deployed on Azure App Service as an example).

For the above components, we need to ensure the following:
- **Private endpoints**: The AI services should be exposed through private endpoints.
- **Private DNS zone**: A private DNS zone to resolve the private endpoints for the connected Azure AI services.
- **APIM Managed identity**: Is granted access to Azure AI services (like OpenAI and AI Search).
- **Update endpoint and keys**: The backend services should use AI Hub Gateway endpoint and keys.
- **Usage & charge-back**: Identify the data pipeline for tokens usage and charge back based on Event Hub integration.

### Deployment summary

When deployment of primary components is completed, you will have the following components deployed:

- **Azure API Management**
- **Application Insights**
- **Event Hub**

Network wiring also will be established to allow the gateway to access the AI services through private endpoints, internet access through DMZ appliances and backend systems through private network.

with the additional components deployed, you will have the following components identified:
- **Azure OpenAI** endpoints
- **Azure AI Search** endpoints
- **Backend services** updated endpoints and keys
- **Usage & charge-back** data pipeline (like pushing data to Cosmos DB and Synapse Analytics)

## Azure API Management configuration
To configure Azure API Management to expose the AI services through the AI Hub Gateway Landing Zone, you will need to configure the following:

- **APIs**: Import APIs definitions to APIM.
- **Products**: Create products to bundle one or more APIs under a common access terms/policies.
- **Policies**: Apply policies to the APIs to manage access, rate limits, and other governance policies.

### APIs import
In this guide, I will be importing both OpenAI and AI Search APIs to APIM.

Many Azure services APIs are available in [Azure REST API specs](https://github.com/Azure/azure-rest-api-specs/tree/main) reference on GitHub.

#### Azure OpenAI API
Although I have included the OpenAI API definition [in this repository](../src/apim/oai-api/oai-api-spec-2024-02-01.yaml), you can also find the Azure OpenAI API definition in here: [Azure OpenAI API](https://github.com/Azure/azure-rest-api-specs/tree/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference)

One included in the repository is inference version 2024-02-01 stable.

Only main change you need to do in the downloaded API definition is to update ```"url": "https://{endpoint}/openai",``` to ```"url": "https://TO-BE-RELACED/openai",``` to avoid conflict with APIM import validation.

> **Important**: You need to append ```/openai``` to your selected ```API URL suffix``` in APIM import dialog to be something like (ai-hub-gw/openai). This is important as OpenAI SDK append /openai to the endpoint URL (not doing so you might get 404 errors from the client connecting to AI Hub Gateway endpoint).

One last thing, you need to update APIM subscription header name from ```Ocp-Apim-Subscription-Key``` to ```api-key``` to match the OpenAI SDK default implementation (not doing so you might get 401 unauthorized error).

#### Azure AI Search API
Same story with Azure AI Search, you can find a local copy [in this repository](../src/apim/ai-search-api/ai-search-api-spec.yaml).

I had to make few additional changes to the downloaded API definition to make it work with APIM import 
validation.

Public documentation for AI Search API can be found here: [Azure AI Search API](https://github.com/Azure/azure-rest-api-specs/tree/main/specification/search/data-plane/Azure.Search) (I used stable 2023-11-01 version).