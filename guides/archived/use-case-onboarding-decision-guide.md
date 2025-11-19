# AI Hub Gateway: use-case Onboarding Decision Guide

## Executive Summary

The AI Hub Gateway serves as a central control point for consuming Generative AI services across an organization. Each business unit or team requiring AI capabilities will have unique operational requirements, security considerations, and performance needs. This guide outlines the key decisions that must be made when onboarding a new use-case to the AI Hub Gateway, especially focusing on scenarios that require multiple AI services working in tandem.

Modern enterprise AI solutions frequently require orchestration of multiple AI services - such as OpenAI models, Azure AI Search, Document Intelligence, Llama 3, and other foundation models - to deliver comprehensive functionality. The AI Hub Gateway enables unified governance, security, and observability across these multi-service solutions.

APIM (API Management) Product policies are the cornerstone of tailoring the AI Gateway experience for different use-cases. They allow for fine-grained control over:
- Access to multiple AI services within a single use-case
- Traffic management across various services
- Consistent security features across the service spectrum
- Unified observability for the entire solution

By properly configuring these policies, organizations can ensure each use-case gets the appropriate level of service while maintaining organizational governance across the complex multi-service landscape.

This guide presents a structured approach to making these decisions, along with a decision template that can be filled out for each use-case. We also provide concrete examples that demonstrate different policy configurations - including scenarios that leverage multiple AI services to solve complex business problems.

## Key Decision Areas for AI Gateway use-cases

When bringing a new business use-case to the AI Hub Gateway, several critical decisions need to be made that will affect the configuration of the APIM Product policy. These decisions fall into the following categories:

### 1. Authentication and Security

The AI Hub Gateway supports multiple authentication approaches to meet different security requirements:

- **Basic Authentication**: APIM subscription keys only - suitable for internal or less sensitive use-cases
- **Enhanced Authentication**: APIM subscription keys + JWT token validation with Microsoft Entra ID - required for sensitive use-cases

For JWT token validation, the gateway offers two implementation approaches:

#### Standard Entra ID Authentication
Uses APIM named values for configuration and is suitable when all APIs in a product use the same authentication requirements:
- **Entra ID Integration**: Uses global named values (`entra-auth`, `tenant-id`, `audience`, `client-id`)
- **Product-Level Configuration**: Consistent authentication across all APIs in the product
- **Simpler Management**: Centralized configuration through APIM named values

#### Custom Entra ID Authentication  
Uses policy variables for flexible, use-case-specific configuration within the same product:
- **API-Specific Configuration**: Different authentication parameters per API or operation
- **Dynamic Authentication**: Conditional authentication based on request characteristics
- **Multi-Tenant Support**: Different tenant configurations within the same product

**Key Decision Points:**
- **Authentication Method**: Subscription keys only, or subscription keys + JWT validation?
- **JWT Approach**: Standard (named values) or Custom (policy variables)?
- **Application Registration**: Which specific client applications should be allowed?
- **Tenant Scoping**: Single tenant or multi-tenant support required?
- **Conditional Authentication**: Do different APIs within the product need different auth requirements?

### 2. Backend Access Control

- **Regional Access**: Should the use-case have access to all available backend AI services or be restricted to specific backends (used to restrict traffic to specific regions due regulatory or performance requirements)?

### 3. Multi-Service AI Requirements

Standard recommendation is to create single APIM product for each AI service that a use-case requires (so a single use case may have multiple APIM Products/Subscriptions to avail different AI services with unique key for each), but in some cases it may be necessary to combine multiple AI services into a single product. This is especially true for complex use-cases that require orchestration of multiple AI services to deliver end-to-end functionality.

>**NOTE:** Consider only this section if your use-case requires multiple AI services to work together. If the use-case only requires a single AI service or if you will be creating separate APIM products for the different AI services required, you can skip this section and focus on the other decision areas. 

Refer to [Multi-Service AI Requirements Guide](./use-case-onboarding-multi-service-guide.md) for detailed guidance on how to configure multi-service AI use-cases. 

### 4. Model Access Control

For each AI service, it can offer multiple models, deployments, indexes, or other resources that need to be controlled. This section focuses on how to manage access to these sub-resources.

- **Model Restrictions**: Which AI models should the use-case have access to?

### 5. Content Safety Controls (OPTIONAL)

This section is exclusive for LLM or Generative AI services to provide content safety controls. It is not applicable for traditional AI services like AI Search or Document Intelligence services. 

Although, Azure OpenAI offer content safety protection as service level, you may want to adjust content safety configurations based on the specific use-case requirements or if you are using other LLM that do not offer this. This section focuses on how to configure content safety controls for each LLM AI service.

- **Content Safety Requirements**: What level of content filtering is required?
- **Shield Prompt**: Should the service use a shield prompt to mitigate prompt injection attacks?
- **Content Categories**: Which content categories (hate, violence, sexual, self-harm, etc.) should be monitored and at what threshold levels?
- **Input/Output Filtering**: Which services require input filtering, output filtering, or both?

### 6. Capacity Management
This is the control the capacity of the AI services used by the use-case. It is important to ensure that the use-case does not exceed the capacity limits of the AI services, especially when multiple AI services are used together.

While assigning capacity limits, you need to consider the following:
- Criticality of the use-case: Is it mission-critical or can it tolerate some downtime?
- Expected usage patterns: Will the use-case have high or low traffic? 
- Does it have predictable traffic patterns or is it bursty?
- Is it for internal use only or will it be exposed to external users?

Capacity also differs based on the AI service/model used, so you need to consider the following:

#### Token based AI Services
- **Token Limits**: What are the appropriate token rate limits for this use-case?
   - At the subscription level
   - At the product level (across all subscriptions)
   - Per-model limits or for all models allowed in the product
- **Token Quotas**: Should there be monthly/weekly token quotas?

#### Non-Token based AI Services
- **Rate Limits**: What are the appropriate rate limits for this use-case?
   - Per minute/hour/day
   - Per subscription or product

### 7. PII Handling (OPTIONAL)

This section is relevant for use-cases that involve processing personally identifiable information (PII). It focuses on how to handle PII detection, anonymization, and deanonymization across multiple AI services for specific use-cases that requires it.

- **PII Detection and Processing**: Does this use-case involve sensitive personally identifiable information?
- **Anonymization Requirements**: Is PII anonymization needed for regulatory or privacy reasons?
- **PII entity Categories**: Which PII categories need to be detected and anonymized?
- **Custom PII Patterns**: Are there industry-specific or organization-specific PII patterns that require detection?
- **Language Support**: What languages should PII detection support (e.g., English, auto-detect)?

### 8. Usage Tracking and Monitoring

- **Chargebacks**: Will this use-case require internal chargebacks for AI usage?
- **Usage Metrics**: What metrics are needed for this specific use-case?
- **Session/User Tracking**: Does this use-case require tracking at the session or user level?
- **Custom Dimensions**: Are there any additional dimensions that need to be tracked for this use-case?

### 9. Error Handling

- **Throttling Strategy**: How should the system respond when capacity limits are reached? (like raising Azure Alter if throttling occurs more than 10 time in the last 5 minutes)
- **Retry Policies**: Do you support having a backup AI services in-case of throttling or service unavailability of the main AI backend?

### 10. Product Naming Conventions

Having a consistent naming convention for APIM products is crucial for governance, especially in environments with multiple use-cases, departments, and staging environments. The following considerations should guide your product naming strategy:

- **AI Service Type Prefix**: Prefix the product name with an abbreviation of the AI service type (e.g., "OAI-" for OpenAI, "AISRCH-" for AI Search, "MULTI-" for multi-AI-service solutions)
- **Department/Team Identifier**: Include the business unit or team name in the product (e.g., "HR", "RETAIL", "FINANCE")
- **use-case Type**: Indicate the primary purpose or capability (e.g., "ASSISTANT", "SEARCH", "AGENT")
- **Special Processing Indicator**: Add suffixes for special processing requirements (e.g., "PII" for products with PII handling)
- **Environment Designation**: For shared gateways across environments, include environment identifiers (e.g., "-DEV", "-TEST", "-PROD")

Below are a few examples of how to structure product names based on these conventions:

| Prefix | Department/Team | use-case Type | Special Processing | Environment | Example Product Name |
|--------|------------------|----------------|--------------------|-------------|----------------------|
| OAI    | HR               | ASSISTANT      | PII                | PROD        | OAI-HR-ASSISTANT-PII-PROD |
| OAI    | RETAIL           | ASSISTANT      |                    | PROD        | OAI-RETAIL-ASSISTANT-PROD |
| OAI    | RETAIL           | COPILOT        |                    | DEV         | OAI-RETAIL-COPILOT-DEV |
| AISRCH | FINANCE          | DOCS           |                    | TEST        | AISRCH-FINANCE-DOCS-TEST |
| MULTI  | LEGAL           | RAG            | PII                | PROD        | MULTI-LEGAL-RAG-PII-PROD |

#### Example Product Naming Patterns as part of the onboarding template:

| Product Name | Description |
|-------------|-------------|
| OAI-HR-ASSISTANT-PII-PROD | OpenAI HR assistant with PII processing in production |
| OAI-RETAIL-COPILOT-DEV | OpenAI retail copilot in development environment |
| AISRCH-FINANCE-DOCS-TEST | AI Search for financial documents in test environment |
| MULTI-LEGAL-RAG-PROD | Multi-service legal RAG solution (OpenAI + AI Search) in production |
| MULTI-CUSTSERV-AGENT-DEV | Multi-service customer service agent (GPT + Llama + Doc Intelligence) in development |
| DOC-SALES-ANALYTICS-TEST | Document Intelligence sales analytics solution in test environment |
| OAI-LEGAL-CONTRACT-ANALYZER | OpenAI legal contract analysis service |

Following a consistent naming convention makes it easier to:
1. Identify the purpose and ownership of each product
2. Apply appropriate governance controls
3. Track usage and allocate costs
4. Manage lifecycle across different environments

## Decision Template for New use-cases

When onboarding a new use-case to the AI Hub Gateway, complete the following template to guide policy configuration:

```
# AI Gateway use-case Onboarding Template

## use-case Information
- Name: [Name of the use-case]
- Description: [Brief description of the use-case]
- Business Unit/Team: [Which team/department owns this use-case]
- Contact Person: [Primary technical contact]

## Product Naming
- AI Service Prefix: [e.g., OAI for OpenAI, AISRCH for AI Search, MULTI for multi-service]
- Department/Team Code: [Short code for the business unit]
- use-case Type: [e.g., ASSISTANT, SEARCH, AGENT, RAG]
- Special Processing Indicator: [e.g., PII, if applicable]
- Environment: [DEV, TEST, PROD, etc.]
- Proposed Product Name: [Following the convention, e.g., MULTI-HR-RAG-PII-PROD]

## Authentication and Security Requirements
- Authentication Method: [Subscription keys only / Subscription keys + JWT validation]
- JWT Authentication Approach: [Standard (named values) / Custom (policy variables) / N/A]
- Entra ID Integration: [Yes/No]
- Tenant ID: [ID of the Microsoft Entra tenant to authorize, or "Multiple" for multi-tenant]
- Client Application ID: [ID of the registered application, or "Multiple" for different apps per API]
- Audience Value: [Expected audience claim value in tokens, or "Dynamic" for variable audiences]
- Additional Required Claims: [Any other claims that should be validated, e.g., groups, roles]
- Multi-Tenant Requirements: [Yes/No - if Yes, specify tenant selection strategy]
- Conditional Authentication: [Yes/No - if Yes, specify conditions for different auth requirements]

## Backend Access Requirements
- Allowed Backends: [List of allowed backend IDs, or "All"]
- Highlight Regional Restrictions: [Yes/No, if Yes - specify regions]

## Model Access Requirements (Per AI service sub-models or resources)
- Allowed Models: [List specific model deployments required]

## Content Safety Configuration (Per AI service sub-models or resources)
- Content Safety Required: [Yes/No]
- Categories to Monitor: [List categories and their thresholds, e.g., Hate: 4, Violence: 4]
- Shield Prompt: [True/False]
- Input/Output Filtering Requirements: [Which services need input/output filtering]

## Capacity Management (Per AI service sub-models or resources)
- Subscription-level Token/API-Calls Rate Limit (TPM): [e.g., 10000 tokens per minute]
- Product-level Total Token/API-Calls Rate Limit (TPM): [e.g., 15000 tokens per minute]
- Token/API-Calls Quota: [e.g., 100000 monthly]
- Token/API-Calls Quota Period: [Monthly/Weekly/Daily]
- Service-Specific Capacity Limits: [Any service-specific limitations beyond the above limits]

## PII Processing Requirements (Per AI service sub-models or resources)
- PII Anonymization Required: [Yes/No]
- PII Detection Language: [en, auto, etc.]
- PII Confidence Threshold: [e.g., 0.75]
- PII Entity Category Exclusions: [List any PII categories to exclude]
- Custom PII Regular-Expressions Patterns: [List any custom regex patterns needed]

## Usage Tracking Requirements
- Chargeback Required: [Yes/No]
- Session/User Level Tracking: [Yes/No]
- Custom Dimensions Required: [List any additional tracking dimensions]
- Any custom dashboards or reports needed: [Yes/No, if Yes - specify]

## Error Handling Strategy
- Retry-after Behavior: [How to handle retry-after headers]
- Throttling alerts: [Custom message or standard and what are the thresholds to trigger them]
- Fallback Options: [Alternative paths when primary service is unavailable]

## Additional Requirements
- [Any other specific requirements for this use-case]
```

## Example use-cases

Below we demonstrate example use-cases with different requirements and their corresponding APIM product policies:

### Example 1: HR Assistant with PII Processing (Standard JWT Authentication)

This use-case requires comprehensive features including PII anonymization, content safety, and detailed capacity management using the standard JWT authentication approach.

#### use-case Information
- Name: HR PII Assistant
- Description: Offering OpenAI services for internal HR platforms with PII anonymization processing
- Business Unit/Team: Human Resources
- Contact: HR Technology Team

#### Product Naming
- AI Service Prefix: OAI (OpenAI)
- Department/Team Code: HR
- use-case Type: ASSISTANT
- Special Processing Indicator: PII
- Environment: PROD
- Product Name: OAI-HR-ASSISTANT-PII-PROD

#### Authentication and Security
- Authentication Method: Subscription keys + JWT validation
- JWT Authentication Approach: Standard (named values)
- Entra ID Integration: Yes
- Tenant ID: contoso.onmicrosoft.com (configured in named values)
- Client Application ID: hr-employee-portal-app (configured in named values)
- Audience Value: api://hr-assistant.contoso.com (configured in named values)
- Additional Claims Required: groups (must contain 'HR-Employee-Portal-Users')

#### APIM Product Policy Configuration

```xml
<policies>
    <inbound>
        <base />

        <!-- Enable standard JWT token validation with Entra ID using named values -->
        <include-fragment fragment-id="aad-auth" />

        <!-- Defining allowed backends to be used by this product (used to restrict traffic to certain regions) -->
        <!-- Backend RBAC: Set allowed backends (comma-separated backend-ids, empty means all are allowed) -->
        <set-variable name="allowedBackend" value="openai-backend-0" />

        <!-- Restrict access for this product to specific models -->
        <choose>
            <when condition="@(!new [] { "gpt-4o", "embedding" }.Contains(context.Request.MatchedParameters["deployment-id"] ?? String.Empty))">
                <return-response>
                    <set-status code="401" reason="Unauthorized model access" />
                </return-response>
            </when>
        </choose>

        <!-- Adding content safety with customized option for the product -->
        <!-- Failure to pass content safety will result in 403 error -->
        <llm-content-safety backend-id="content-safety-backend" shield-prompt="true">
            <categories output-type="EightSeverityLevels">
                <category name="Hate" threshold="4" />
                <category name="Violence" threshold="4" />
            </categories>
        </llm-content-safety>

        <!-- Capacity management - Subscription Level: allow only assigned tpm for each HR use-case subscription -->
        <set-variable name="target-deployment" value="@((string)context.Request.MatchedParameters["deployment-id"])" />
        <choose>
            <when condition="@((string)context.Variables["target-deployment"] == "gpt-4o")">
                <azure-openai-token-limit 
                    counter-key="@(context.Subscription.Id + "-" + context.Variables["target-deployment"])" 
                    tokens-per-minute="10000" 
                    estimate-prompt-tokens="false" 
                    tokens-consumed-header-name="consumed-tokens" 
                    remaining-tokens-header-name="remaining-tokens" 
                    token-quota="100000"
                    token-quota-period="Monthly"
                    retry-after-header-name="retry-after" />
            </when>
            <otherwise>
                <azure-openai-token-limit 
                    counter-key="@(context.Subscription.Id + "-default")" 
                    tokens-per-minute="1000" 
                    estimate-prompt-tokens="false" 
                    tokens-consumed-header-name="consumed-tokens" 
                    remaining-tokens-header-name="remaining-tokens" 
                    token-quota="5000"
                    token-quota-period="Monthly"
                    retry-after-header-name="retry-after" />
            </otherwise>
        </choose>
        
        <!-- Capacity management: Product Level (across all OpenAI models -->
        <azure-openai-token-limit 
                    counter-key="@(context.Product?.Name?.ToString() ?? "Portal-Admin")" 
                    tokens-per-minute="15000" 
                    estimate-prompt-tokens="false" 
                    tokens-consumed-header-name="consumed-tokens" 
                    remaining-tokens-header-name="remaining-tokens" 
                    token-quota="150000"
                    token-quota-period="Monthly"
                    retry-after-header-name="retry-after" />

        <!-- PII Detection and Anonymization -->
        <set-variable name="piiAnonymizationEnabled" value="true" />
        <!-- Variables required by pii-anonymization fragment -->
        <choose>
            <when condition="@(context.Variables.GetValueOrDefault<string>("piiAnonymizationEnabled") == "true")">
                <!-- Configure PII detection settings -->
                <set-variable name="piiConfidenceThreshold" value="0.75" />
                <set-variable name="piiEntityCategoryExclusions" value="PersonType,CADriversLicenseNumber" />
                <set-variable name="piiDetectionLanguage" value="en" /> <!-- Use 'auto' if context have multiple languages -->

                <!-- Configure regex patterns for custom PII detection -->
                <set-variable name="piiRegexPatterns" value="@{
                    var patterns = new JArray {
                        new JObject {
                            ["pattern"] = @"\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b",
                            ["category"] = "CREDIT_CARD"
                        },
                        new JObject {
                            ["pattern"] = @"\b[A-Z]{2}\d{6}[A-Z]\b",
                            ["category"] = "PASSPORT_NUMBER"
                        },
                        new JObject {
                            ["pattern"] = @"\b\d{3}[-]?\d{4}[-]?\d{7}[-]?\d{1}\b",
                            ["category"] = "NATIONAL_ID"
                        }
                    };
                    return patterns.ToString();
                }" />
                <set-variable name="piiInputContent" value="@(context.Request.Body.As<string>(preserveContent: true))" />
                <!-- Include the PII anonymization fragment -->
                <include-fragment fragment-id="pii-anonymization" />
                <!-- Replace the request body with anonymized content -->
                <set-body>@(context.Variables.GetValueOrDefault<string>("piiAnonymizedContent"))</set-body>
            </when>
        </choose>
    
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        <!-- PII Deanonymization -->
        <set-variable name="responseBodyContent" value="@(context.Response.Body.As<string>(preserveContent: true))" />
        <choose>
            <when condition="@(context.Variables.GetValueOrDefault<string>("piiAnonymizationEnabled") == "true" && 
                            context.Variables.ContainsKey("piiMappings"))">
                <!-- Use stored response body for deanonymization -->
                <set-variable name="piiDeanonymizeContentInput" value="@(context.Variables.GetValueOrDefault<string>("responseBodyContent"))" />
                <include-fragment fragment-id="pii-deanonymization" />
                <!-- Variables required by pii-state-saving fragment -->
                <set-variable name="piiStateSavingEnabled" value="true" />
                <set-variable name="originalRequest" value="@(context.Variables.GetValueOrDefault<string>("piiInputContent"))" />
                <set-variable name="originalResponse" value="@(context.Variables.GetValueOrDefault<string>("responseBodyContent"))" />
                
                <!-- RECOMMENDED FOR TESTING ONLY: Include the PII state saving fragment to push pii detection results to event hub -->
                <include-fragment fragment-id="pii-state-saving" />
                
                <!-- Replace response with deanonymized content -->
                <set-body>@(context.Variables.GetValueOrDefault<string>("piiDeanonymizedContentOutput"))</set-body>
            </when>
            <otherwise>
                <!-- Pass through original response using stored content -->
                <set-body>@(context.Variables.GetValueOrDefault<string>("responseBodyContent"))</set-body>
            </otherwise>
        </choose>
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

### Example 2: Retail Assistant with Basic Controls (No JWT Authentication)

This use-case requires only basic model restrictions and capacity management, without the need for JWT authentication, PII processing or advanced content safety.

#### use-case Information
- Name: Retail Assistant
- Description: Offering OpenAI services for retail and e-commerce platforms assistant
- Business Unit/Team: Retail Operations
- Contact: Digital Store Team

#### Product Naming
- AI Service Prefix: OAI (OpenAI)
- Department/Team Code: RETAIL
- use-case Type: ASSISTANT
- Special Processing Indicator: (None)
- Environment: PROD
- Product Name: OAI-RETAIL-ASSISTANT-PROD

#### Authentication and Security
- Authentication Method: Subscription keys only
- JWT Authentication Approach: N/A
- Entra ID Integration: No
- Tenant ID: N/A
- Client Application ID: N/A
- Audience Value: N/A
- Additional Claims Required: N/A

#### APIM Product Policy Configuration

```xml
<policies>
    <inbound>
        <base />
        <!-- No JWT authentication required for this use-case -->
        
        <!-- Restrict access for this product to specific models -->
        <choose>
            <when condition="@(!new [] { "gpt-4o", "chat", "embedding" }.Contains(context.Request.MatchedParameters["deployment-id"] ?? String.Empty))">
                <return-response>
                    <set-status code="401" reason="Unauthorized model access" />
                </return-response>
            </when>
        </choose>

        <!-- Capacity management: allow only assigned tpm for each Retail use-case subscritpion -->
        <azure-openai-token-limit counter-key="@(context.Subscription.Id)" 
            tokens-per-minute="10000" 
            estimate-prompt-tokens="true" 
            tokens-consumed-header-name="consumed-tokens" 
            remaining-tokens-header-name="remaining-tokens" 
            retry-after-header-name="retry-after" />

    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

## Decision Impact Analysis

The examples above demonstrate how different business requirements influence policy configuration:

### Authentication Features Comparison

| Feature | HR Assistant | Retail Assistant | Legal RAG System | Finance Multi-Tenant |
|---------|-------------|-----------------|------------------|---------------------|
| Product Name | OAI-HR-ASSISTANT-PII-PROD | OAI-RETAIL-ASSISTANT-PROD | MULTI-LEGAL-RAG-PII-PROD | OAI-FINANCE-ASSISTANT-MULTITENANT-PROD |
| Authentication Method | Subscription Key + JWT | Subscription Key only | Subscription Key + JWT | Subscription Key + JWT |
| JWT Approach | Standard (named values) | N/A | Custom (policy variables) | Custom (policy variables) |
| Entra ID Integration | Yes (single tenant) | No | Yes (service-specific clients) | Yes (multi-tenant) |
| Client Application | Single app | N/A | Multiple apps per service | Dynamic per tenant |
| Audience Configuration | Static (named value) | N/A | Dynamic per service | Dynamic per tenant |
| Conditional Logic | No | No | Service-based | Tenant-based |
| Configuration Complexity | Low | Minimal | High | High |

### Authentication Architecture Impact

1. **Standard JWT Authentication**:
   - **Pros**: Simple configuration, consistent across product, centralized management
   - **Cons**: Less flexible, single configuration for all APIs
   - **Best For**: Uniform authentication requirements across all APIs in product

2. **Custom JWT Authentication**:
   - **Pros**: Flexible per-API configuration, supports complex scenarios, dynamic authentication
   - **Cons**: More complex policy logic, distributed configuration
   - **Best For**: Multi-service products, multi-tenant scenarios, varying authentication needs

3. **No JWT Authentication**:
   - **Pros**: Simplest configuration, lowest overhead
   - **Cons**: Less secure, relies only on subscription keys
   - **Best For**: Internal use-cases, non-sensitive data, development environments

## Conclusion

Designing the right APIM Product policy for each AI use-case requires balancing multiple factors including security, performance, compliance, and business needs. The decision template provided in this guide helps structure this decision-making process, with special attention to multi-service AI scenarios.

By reviewing the examples shown, teams can better understand how to configure policies that match their specific requirements. The single-service examples demonstrate focused controls, while the multi-service Legal RAG System example shows how to handle complex orchestration of multiple AI services under a unified governance model.

As organizations expand their use of generative AI, the integration of multiple AI services becomes increasingly common. Proper design of gateway policies for these complex scenarios ensures that organizations can leverage the full power of various AI services while maintaining consistent security, compliance, and operational controls.

Remember that these policies can be adjusted over time as needs evolve and usage patterns become more apparent. Regular reviews of product configurations are recommended to ensure they continue to meet business requirements and performance expectations.

## References

For more detailed guidance on specific aspects of AI Hub Gateway configuration and use-cases, refer to these related guides:

### Core Configuration Guides
- [APIM Configuration](./apim-configuration.md) - Detailed guide on API Management policies and configuration
- [Architecture Overview](./architecture.md) - Understanding the overall architecture of AI Hub Gateway
- [Deployment Guide](./deployment.md) - Step-by-step instructions for deploying AI Hub Gateway

### Feature-specific Guides
- [PII Masking in APIM](./pii-masking-apim.md) - Comprehensive guide on implementing PII anonymization/deanonymization
- [Dynamic Throttling Assignment](./dynamic-throttling-assignment.md) - Managing token rate limits dynamically
- [OpenAI Usage Ingestion](./openai-usage-ingestion.md) - Tracking and analyzing usage metrics
- [Throttling Events Handling](./throttling-events-handling.md) - Managing and responding to throttling events
- [Power BI Dashboard](./power-bi-dashboard.md) - Creating dashboards for AI usage analytics

### Integration Guides
- [AI Studio Integration](./ai-studio-integration.md) - Connecting AI Hub Gateway with Azure AI Studio
- [AI Search Integration](./ai-search-integration.md) - Integrating Azure AI Search with AI Hub Gateway


### Troubleshooting
- [Deployment Troubleshooting](./deployment-troubleshooting.md) - Solutions for common deployment issues
- [OpenAI Onboarding](./openai-onboarding.md) - Guidance for onboarding new OpenAI models
