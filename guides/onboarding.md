# Onboarding an OpenAI Instance or Consumer Application

This guide will walk you through the steps to configure Azure API Management (APIM) to work with a new consumer or Azure OpenAI deployment.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Step-by-Step Configuration: Onboarding a New Azure OpenAI Resource](#step-by-step-configuration-onboarding-a-new-azure-openai-resource)
    1. [Ensure Line of Sight to OpenAI](#1-ensure-line-of-sight-to-openai)
    2. [Grant OpenAI User Access to APIM User Managed Identity](#2-grant-openai-user-access-to-apim-user-managed-identity)
    3. [Identify All Deployment Names Associated with OpenAI](#3-identify-all-deployment-names-associated-with-openai)
    4. [Create APIM Backend for OpenAI](#4-create-apim-backend-for-openai)
    6. [Update Routing Configuration](#5-update-routing-configuration)
    7. [Testing the Revision](#6-testing-the-revision)
    8. [Marking Revision as Current](#7-marking-revision-as-current)
    9. [Enforcing Deployment-Level RBAC](#8-enforcing-deployment-level-rbac)
3. [Step-by-Step Configuration: Onboarding a New Consumer](#step-by-step-configuration-onboarding-a-new-consumer)
    1. [Create New Product](#1-create-new-product)
    2. [Create New Subscription for the Product](#2-create-new-subscription-for-the-product)
    3. [Share APIM OpenAI Endpoint, Subscription Key, and Available Models](#3-share-apim-openai-endpoint-subscription-key-and-available-models)

## Prerequisites

Before starting, make sure you have:
- An operational AI Hub Gateway deplyoment.
- Access to the Azure OpenAI service if you are adding a new deployment.
- Azure Portal access.

## Step-by-Step Configuration: Onboarding a New Azure OpenAI Resource

### 1. Ensure Line of Sight to OpenAI

**Steps:**

1. **Azure Portal:**
   - Navigate to your Virtual Network (VNet) where APIM is deployed.
   - Go to **DNS Servers** and ensure you have the correct DNS settings for resolving OpenAI endpoints.

2. **DNS Configuration:**
   - If you're using custom DNS, ensure the DNS server can resolve OpenAI service endpoints.
   - You may need to add custom DNS entries to your DNS server for OpenAI services.
  
3. **Network Configuration:**
   - Ensure that network connectivity is available between API Management and the Azure OpenAI Resource. If your Azure OpenAI Resource does not allow public networking, you may need to add a private endpoint in your Virtual Network. See: [Use private endpoints](https://learn.microsoft.com/en-us/azure/ai-services/cognitive-services-virtual-networks?tabs=portal#use-private-endpoints).

### 2. Grant OpenAI User Access to APIM User Managed Identity

The identity of the Azure API Management needs access to perform inference calls on the AI Models.

**Steps:**

1. **Azure Portal:**
   - Navigate to your Azure API Management instance.
   - Go to **Managed identities** under **Security** and ensure it is enabled.

2. **Role Assignment:**
   - Navigate to your Azure OpenAI resource.
   - Go to **Access Control (IAM)** and click **Add role assignment**.
   - Select **Cognitive Services OpenAI User** role. See: [Role-based access control](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/role-based-access-control).
   - Assign this role to the APIM Managed Identity.

### 3. Identify All Deployment Names Associated with OpenAI

**Steps:**

1. **Azure Portal:**
   - Navigate to your Azure OpenAI resource.
   - Under **Deployments**, note down the names of all the deployments you have created. 

### 4. Create APIM Backend for OpenAI

> [!TIP]
> Ensure that your backend-url ends with /openai

**Steps:**

1. **Azure Portal:**
   - Navigate to your Azure API Management instance.
   - Go to **Backends** under **APIs**.
   - Click **+ Add** to create a new backend.
   - Configure the backend with the OpenAI endpoint URL and name it appropriately (it should end with `/openai/`).

### 5. Update Routing Configuration

**Steps:**

1. **Azure Portal:**
   - Navigate to your Azure API Management instance.
   - Go to **APIs**, select the OpenAI API, and navigate to **Design**.
   - Go to the menu on the **OpenAI API** and select **Add Revision** to create a new revision (to avoid downtime during implementation).
   - Under **Inbound processing**, update the policy to include the new routes and clusters for OpenAI deployments.

**Sample Configuration:**

```xml
<set-variable name="oaClusters" value="@{
    // route is an Azure OpenAI API endpoint
    JArray routes = new JArray();
    JArray clusters = new JArray();
    
    routes.Add(new JObject()
    {
        { "name", "EastUS" },
        { "location", "eastus" },
        { "backend-id", "openai-backend-0" },
        { "priority", 1},
        { "isThrottling", false }, 
        { "retryAfter", DateTime.MinValue } 
    });

    clusters.Add(new JObject()
    {
        { "deploymentName", "chat" },
        { "routes", new JArray(routes[0]) }
    });

    return clusters;   
}" />
```

Ensure that the backend is linked with all available deployments for that endpoint by updating the clusters variable accordingly.

### 6. Testing the Revision

**Steps:**

1. **Azure Portal:**
   - Navigate to your Azure API Management instance.
   - Go to **APIs** and select the OpenAI API.
   - Under **Test**, select the new revision and test the API endpoints to ensure they are working as expected.

### 7. Marking Revision as Current

**Steps:**

1. **Azure Portal:**
   - Navigate to your Azure API Management instance.
   - Go to **APIs**, select the OpenAI API, and navigate to **Revisions**.
   - Select the new revision and click **Make current**.

### 8. Enforcing Deployment-Level RBAC

In some cases, you might want to restrict access to specific models based on the business unit or team using the OpenAI endpoint. 

The following policy can be implemented at a product level to restrict access to specific model deployments. For more details, refer to the [Model-based RBAC guide](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/blob/main/guides/apim-configuration.md#model-based-rbac).

> [!CAUTION]
> This policy will restrict access to only two deployments (gpt-4 and embedding). Any other model deployment will get a 401 Unauthorized response.

**Sample Policy:**

```xml
<inbound>
    <base />
    <!-- Restrict access for this product to specific models -->
    <choose>
        <when condition="@(!new [] { 'gpt-4', 'embedding' }.Contains(context.Request.MatchedParameters['deployment-id'] ?? String.Empty))">
            <return-response>
                <set-status code="401" reason="Unauthorized" />
            </return-response>
        </when>
    </choose>
</inbound>
```


## Step-by-Step Configuration: Onboarding a New Consumer

### 1. Create New Product

**Steps:**

1. **Azure Portal:**
   - Navigate to your Azure API Management instance.
   - Go to **Products** and click **+ Add**.
   - Configure the product with the appropriate settings for token throughput capacity and access to specific models (using product-level policies).

### 2. Create New Subscription for the Product

**Steps:**

1. **Azure Portal:**
   - Navigate to your Azure API Management instance.
   - Go to **Products**, select the newly created product, and navigate to **Subscriptions**.
   - Click **+ Add** to create a new subscription.
   - Provide the necessary details and generate a subscription key.

### 3. Share APIM OpenAI Endpoint, Subscription Key, and Available Models

**Steps:**

1. **Azure Portal:**
   - Navigate to your Azure API Management instance.
   - Go to **APIs**,

 select the OpenAI API, and copy the endpoint URL.
   - Share the endpoint URL, subscription key, and list of available models with the team.

**Sample Configuration for Sharing:**
> [!CAUTION]
> A subscription key is like a password. Ensure you share it securely.

```plaintext
API Endpoint: https://apim-your-instance.azure-api.net/openai
Subscription Key: {YourSubscriptionKey}
Available Models: gpt-3.5-turbo, gpt-4, dall-e
```
