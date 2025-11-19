## End-to-end scenario (Chat with data)

With the AI Hub Gateway Landing Zone deployed, you can now enable various line-of-business units in your organization to leverage Azure AI services in a secure and governed manner.

In this walkthrough, we will demonstrate an end-to-end scenario of a chat application that uses both Azure OpenAI and Azure AI Search through the AI Hub Gateway Landing Zone.

### Scenario overview

The chat application is designed to provide a conversational interface to users to interact with the AI services exposed through the AI Hub Gateway Landing Zone.

The following is the high level flow of the chat application:

- **Build your knowledge base**: 
    - Using Azure Storage, we will ingest documents and other information sources into a blob based storage
    - Using Azure AI Search, ingested data will be indexed using hybrid index (both keyword and semantic/embedding/vector based) to enable both keyword and semantic search
    - Azure AI Search index query endpoint will be exposed through the AI Hub Gateway Landing Zone
    - The index query endpoint will be used to search and retrieve relevant information from the knowledge base (using hybrid with semantic ranking)
- **Build your chat experience**:
    - Get user input: user prompt + chat history (UX)
    - Check and answer in cache, if new question, proceed with retrieval 
    - Build search query: through LLM, pass in user input with a prompt to generate improved search query 
    - Submit search query to Azure AI Search: to retrieve top N list of relevant documents (best results hybrid + semantic ranking)
    - Getting the answer: submit input, relevant documents and system prompt to LLM for answer

As you can see from the chat experience, the chat application uses both Azure AI Search and Azure OpenAI through the AI Hub Gateway Landing.

Also, the chat application is required to orchestrate multiple AI services calls to provide the functionality, and for that it uses an AI Orchestrator framework like **Semantic Kernel** or **Langchain**.

### Source code

In this guide, I'm using the following `C#` based chat application that can be found here: [https://github.com/Azure-Samples/azure-search-openai-demo-csharp](https://github.com/Azure-Samples/azure-search-openai-demo-csharp)

> **Note**: The source code is a simple chat application that uses Azure AI Search and Azure OpenAI and can be found in multiple languages/frameworks. You can use any language/framework of your choice to build the chat application that can be found here [https://github.com/Azure-Samples/azure-search-openai-demo](https://github.com/Azure-Samples/azure-search-openai-demo)

The above source code is designed to connect directly to Azure AI services through managed identity of Azure Container Apps. 

Minor modifications to chat app code are required to connect to the AI Hub Gateway Landing Zone.

To make deployment simple, just follow the deployment instructions on the repository to have the environment up and running (it uses ```azd``` to provision the required infrastructure and code deployment).

#### Configure APIM to use the new services endpoints

Once the chat app is deployed, you will have a new OpenAI and AI Search services deployed and you will need to update the APIM to use the new services endpoints.

For OpenAI, update the load balancing policy fragment to use the new OpenAI services endpoint.

For AI Search, update the AI Search API definition to use the new AI Search services endpoint.

Create a new APIM Product to use the new OpenAI and AI Search APIs (I've used AI-Marketing as an example).

Create a new subscription to the new product and use the subscription key as the secret value in Azure Key Vault.

As APIM will use its system managed identity to access the AI services, you will need to grant the APIM managed identity access to the new OpenAI and AI Search services.

Head to each service IAM blade and add the APIM managed identity with the required role as per the following:
1. **OpenAI**: ```Cognitive Services OpenAI User``` role
2. **AI Search**: ```Search Index Data Reader``` role

#### Update the endpoint and key

The chat app is using Azure Key Vault to store the AI services endpoints and configurations.

You need to update the following in Azure Key Vault:

1. **Update the endpoint**: Update the endpoint of the AI services to the AI Hub Gateway endpoint (both OpenAI and AI Search).
2. **Update the key**: Update the key of the AI services to the AI Hub Gateway key.
    - Create new secrets in Azure Key Vault to store the gateway keys (```AzureazureOpenAIKey``` and ```AzureAISearchKey```).
    - For the secret values, use the subscription key as the secret value that is configured in the previous step (you can use the same subscription key for OpenAI and Search if both APIs are added to the APIM product).

#### Update the chat app code

The chat app code is using Azure Key Vault to retrieve the AI services endpoints and configurations.

Currently the app is using Azure Container Apps Managed identity to access both Azure OpenAI and AI Search services, we will need to make minor code changes to use the AI Hub Gateway keys instead (stored in Key Vault).

The following is the high level steps to update the chat app code:

**File: app/backend/Extensions/ServiceCollectionExtensions.cs**

For OpenAI client:

From:
```csharp
services.AddSingleton<OpenAIClient>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var useAOAI = config["UseAOAI"] == "true";
    if (useAOAI)
    {
        var azureOpenAiServiceEndpoint = config["AzureOpenAiServiceEndpoint"];
        ArgumentNullException.ThrowIfNullOrEmpty(azureOpenAiServiceEndpoint);

        var openAIClient = new OpenAIClient(new Uri(azureOpenAiServiceEndpoint), s_azureCredential);

        return openAIClient;
    }
    else
    {
        ...
    }
});
```
To:
```csharp
services.AddSingleton<OpenAIClient>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var useAOAI = config["UseAOAI"] == "true";
    if (useAOAI)
    {
        var azureOpenAiServiceEndpoint = config["AzureOpenAiServiceEndpoint"];
        ArgumentNullException.ThrowIfNullOrEmpty(azureOpenAiServiceEndpoint);

        var azureOpenAIKey = config["AzureOpenAIKey"];
        ArgumentNullException.ThrowIfNullOrWhiteSpace(azureOpenAIKey);
        
        var openAIClient = new OpenAIClient(new Uri(azureOpenAiServiceEndpoint), new AzureKeyCredential(azureOpenAIKey));

        return openAIClient;
    }
    else
    {
        ...
    }
});
```
For Azure AI Search:
From:
```csharp
services.AddSingleton<ISearchService, AzureSearchService>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var azureSearchServiceEndpoint = config["AzureSearchServiceEndpoint"];
    ArgumentNullException.ThrowIfNullOrEmpty(azureSearchServiceEndpoint);

    var azureSearchIndex = config["AzureSearchIndex"];
    ArgumentNullException.ThrowIfNullOrEmpty(azureSearchIndex);

    var searchClient = new SearchClient(
                        new Uri(azureSearchServiceEndpoint), azureSearchIndex, s_azureCredential);

    return new AzureSearchService(searchClient);
});
```
To:
```csharp
services.AddSingleton<ISearchService, AzureSearchService>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var azureSearchServiceEndpoint = config["AzureSearchServiceEndpoint"];
    ArgumentNullException.ThrowIfNullOrEmpty(azureSearchServiceEndpoint);

    var azureSearchIndex = config["AzureSearchIndex"];
    ArgumentNullException.ThrowIfNullOrEmpty(azureSearchIndex);

    var azureAISearchKey = config["AzureAISearchKey"];
    ArgumentNullException.ThrowIfNullOrWhiteSpace(azureAISearchKey);
    
    var searchClient = new SearchClient(
                    new Uri(azureSearchServiceEndpoint), azureSearchIndex, new AzureKeyCredential(azureAISearchKey));

    return new AzureSearchService(searchClient);
});
```
**File: app/backend/Services/ReadRetrieveReadChatService.cs**

Semantic Kernel embedding:
From:
```csharp
if (configuration["UseAOAI"] == "false")
{
    ...
}
else
{
    var deployedModelName = configuration["AzureOpenAiChatGptDeployment"];
    ArgumentNullException.ThrowIfNullOrWhiteSpace(deployedModelName);
    var embeddingModelName = configuration["AzureOpenAiEmbeddingDeployment"];
    if (!string.IsNullOrEmpty(embeddingModelName))
    {
        var endpoint = configuration["AzureOpenAiServiceEndpoint"];
        ArgumentNullException.ThrowIfNullOrWhiteSpace(endpoint);
        
        kernelBuilder = kernelBuilder.AddAzureOpenAITextEmbeddingGeneration(embeddingModelName, endpoint, tokenCredential ?? new DefaultAzureCredential());
        kernelBuilder = kernelBuilder.AddAzureOpenAIChatCompletion(deployedModelName, endpoint, tokenCredential ?? new DefaultAzureCredential());
    }
}
```
To:
```csharp
if (configuration["UseAOAI"] == "false")
{
    ...
}
else
{
    var deployedModelName = configuration["AzureOpenAiChatGptDeployment"];
    ArgumentNullException.ThrowIfNullOrWhiteSpace(deployedModelName);
    var embeddingModelName = configuration["AzureOpenAiEmbeddingDeployment"];
    if (!string.IsNullOrEmpty(embeddingModelName))
    {
        var endpoint = configuration["AzureOpenAiServiceEndpoint"];
        ArgumentNullException.ThrowIfNullOrWhiteSpace(endpoint);
        
        var azureOpenAIKey = configuration["AzureOpenAIKey"];
        ArgumentNullException.ThrowIfNullOrWhiteSpace(azureOpenAIKey);

        kernelBuilder = kernelBuilder.AddAzureOpenAITextEmbeddingGeneration(embeddingModelName, endpoint, azureOpenAIKey);
        kernelBuilder = kernelBuilder.AddAzureOpenAIChatCompletion(deployedModelName, endpoint, azureOpenAIKey);
    }
}
```

**File: app/backend/GlobalUsings.cs**
```csharp
...
global using Azure;
...
```

**Testing the changes and redeployment**

After making the code changes, you can test the locally the chat app to ensure that it is using the AI Hub Gateway successfully.

If you would run it locally, you need to set the azure key vault endpoint manually in the code.

Once you are satisfied with the changes, you can redeploy the chat app to Azure.

```bash
azd up
```

```azd``` command would override the endpoint values in the Key Vault with the default ones and also will revoke your access to updating secrets. 
Just add you access again under ```Access policies``` and replace endpoints with the correct values (pointing at the AI Hub Gateway) will fix the issue.