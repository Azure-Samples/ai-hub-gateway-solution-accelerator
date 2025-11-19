# Onboarding Azure Document Intelligence

AI Hub Gateway default provisioning instructions has ```Azure Document Intelligence``` API enabled.

## Overview

AI Hub Gateway creates by default 2 APIs for document intelligence service access.

Currently there are new and old versions of the SDKs accessing the service today.

Azure AI Document Intelligence and Form Recognizer are essentially the same service, but the naming and endpoint paths differ depending on the API version and SDK you're using. Here's how to determine when to use /formrecognizer vs /documentintelligence.

> **Note**: Azure Form Recognizer was renamed to Azure AI Document Intelligence in 2023.

In order to remain compatible with existing applications, both the old and new API versions will be supported for now in the gateway.

### When to Use /formrecognizer
Use this path if:
- You're using older API versions (v2.1, v3.0, v3.1).
- You're working with SDKs like:
  - Azure.AI.FormRecognizer (NuGet)
  - azure-ai-formrecognizer (Python)

Your endpoint looks like:
```https://<your-resource-name>.cognitiveservices.azure.com/formrecognizer/```

### When to Use /documentintelligence
Use this path if:
- You're using API version v4.0 or later.
- You're using the new SDKs:
  - Azure.AI.DocumentIntelligence (NuGet)
  - azure-ai-documentintelligence (Python)

Your endpoint looks like:
```https://<your-resource-name>.cognitiveservices.azure.com/documentintelligence/```

## Prerequisites

The following is required:
- Document Intelligence service
- Networking setup (private endpoint, private DNS,...)
- APIM identity permission.

Once the service is created, networking line-of-sight is configured to Azure API Management (especially if private access is required) and permission ```Cognitive Services User``` granted to API Management ```User Assigned Identity```, you will be ready to onboard the new instance to APIM.

## On-boarding existing Document Intelligence services


### Backend Creation 

Create 2 new backends for each instance of Document Intelligence (if backward compatibility is required).

Each backend will have the URL of the document intelligence service with /formrecognizer or /documentintelligence depending on the API version being used.


### Updating APIM routing configurations:

Hit the ```Policy Designer``` in the Azure portal for each Document Intelligence API to update routing configurations.

Below is example of such routing:

```xml
<set-variable name="oaClusters" value="@{
    // route is an Azure Document Intelligence endpoint
    JArray routes = new JArray();

    // cluster is a group of routes that are capable of serving a specific model name
    JArray clusters = new JArray();

    // Update the below if condition when using multiple APIM gateway regions/SHGW to get different configurations for each region
    if(context.Deployment.Region == "ALL" || true)
    {
        // Adding all Azure Document Intelligence endpoints routes (which are set as APIM Backend)
        routes.Add(new JObject()
        {
            { "name", "Doc-Intelligence-EUS" },
            { "location", "East US" },
            { "backend-id", "REPLACE-BACKEND-ID" },
            { "priority", 1},
            { "isThrottling", false }, 
            { "retryAfter", DateTime.MinValue } 
        });

        // For each model, create a cluster with the routes that can serve it
        clusters.Add(new JObject()
        {
            { "deploymentName", "prebuilt-read" },
            { "routes", new JArray(routes[0]) }
        });

        clusters.Add(new JObject()
        {
            { "deploymentName", "prebuilt-layout" },
            { "routes", new JArray(routes[0]) }
        });

        clusters.Add(new JObject()
        {
            { "deploymentName", "prebuilt-healthInsuranceCard.us" },
            { "routes", new JArray(routes[0]) }
        });

        clusters.Add(new JObject()
        {
            { "deploymentName", "prebuilt-invoice" },
            { "routes", new JArray(routes[0]) }
        });

        clusters.Add(new JObject()
        {
            { "deploymentName", "prebuilt-receipt" },
            { "routes", new JArray(routes[0]) }
        });

        clusters.Add(new JObject()
        {
            { "deploymentName", "prebuilt-idDocument" },
            { "routes", new JArray(routes[0]) }
        });
    }
    else
    {
        //No clusters found for selected region, either return error (default behavior) or set default cluster in the else section
    }
    
    return clusters;   
}" />

```

## Onboarding new consumers

Once the routing is updated, generating access keys for the different use cases is done through APIM Products in a similar fashion to other AI services like OpenAI.

1. Create a new APIM Product for each use case with the suggested naming of ```DOC-<business-unit>-<use-case-name>-<environment>```.
2. Associate the appropriate Document Intelligence API(s) with the Product (like adding both the Form Recognizer and Document Intelligence APIs).
3. Generate and distribute access keys to consumers.


## Usage tracking

By default, each request made to document intelligence is logged as 1 request and reported in the accelerator database and dashboard.

Current usage implementation is simple through associated a fixed cost for the entire service or putting estimated cost per request.

Current implementation does not account for different usage patterns or costs associated with specific models or features (like Document intelligence relies on the number of pages processed).

It can be refined to capture such information and reporting it to the database, but as Document Intelligence operations are asynchronous (one request to analyze and another to retrieve results), it requires a more sophisticated tracking mechanism to correlate requests and responses.
