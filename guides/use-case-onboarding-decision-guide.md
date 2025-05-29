# AI Hub Gateway: Use Case Onboarding Decision Guide for Multi-Service AI Solutions

## Executive Summary

The AI Hub Gateway serves as a central control point for consuming Generative AI services across an organization. Each business unit or team requiring AI capabilities will have unique operational requirements, security considerations, and performance needs. This guide outlines the key decisions that must be made when onboarding a new use case to the AI Hub Gateway, especially focusing on scenarios that require multiple AI services working in tandem.

Modern enterprise AI solutions frequently require orchestration of multiple AI services - such as OpenAI models, Azure AI Search, Document Intelligence, Llama 3, and other foundation models - to deliver comprehensive functionality. The AI Hub Gateway enables unified governance, security, and observability across these multi-service solutions.

APIM (API Management) Product policies are the cornerstone of tailoring the AI Gateway experience for different use cases. They allow for fine-grained control over:
- Access to multiple AI services within a single use case
- Traffic management across various services
- Consistent security features across the service spectrum
- Unified observability for the entire solution

By properly configuring these policies, organizations can ensure each use case gets the appropriate level of service while maintaining organizational governance across the complex multi-service landscape.

This guide presents a structured approach to making these decisions, along with a decision template that can be filled out for each use case. We also provide concrete examples that demonstrate different policy configurations - including scenarios that leverage multiple AI services to solve complex business problems.

## Key Decision Areas for AI Gateway Use Cases

When bringing a new business use case to the AI Hub Gateway, several critical decisions need to be made that will affect the configuration of the APIM Product policy. These decisions fall into the following categories:

### 1. Authentication and Security

- **Authentication Method**: Should the use case rely only on APIM subscription keys, or require additional JWT token validation?
- **Entra ID Integration**: For sensitive use cases, should Microsoft Entra ID (formerly Azure AD) token validation be required?
- **Application Registration**: Which specific client applications should be allowed to access this product?
- **Scoping**: Should access be limited to specific tenants, audiences, or client IDs?

### 2. Backend Access Control

- **Regional Access**: Should the use case have access to all backend AI services or be restricted to specific regions?
- **Backend Selection**: Which backends should be allowed for this product (used to restrict traffic to specific regions)?

### 3. Multi-Service AI Requirements

- **Service Composition**: What combination of AI services does this use case require?
  - OpenAI models (GPT-4o, GPT-4, GPT-3.5 Turbo)
  - Azure AI Search
  - Document Intelligence
  - Open-source models (Llama 3, etc.)
  - Vector databases
  - Retrieval Augmented Generation (RAG) components
- **Service Orchestration**: How will these services communicate with each other?
  - Direct service-to-service communication
  - Client-side orchestration
  - Gateway-managed orchestration

### 4. Model Access Control

- **Model Restrictions**: Which AI models should the use case have access to?
- **Model Permission Categories**: Are there specific model categories (chat, embedding, image generation) required?
- **Cross-Service Model Requirements**: Does the use case need consistent model access across multiple services?

### 5. Content Safety Controls

- **Content Safety Requirements**: What level of content filtering is required?
- **Content Categories**: Which content categories (hate, violence, sexual, self-harm, etc.) should be monitored and at what threshold levels?
- **Cross-Service Content Safety**: How should content safety be managed across different AI services with varying native capabilities?
- **Input/Output Filtering**: Which services require input filtering, output filtering, or both?

### 6. Capacity Management

- **Token Limits**: What are the appropriate token rate limits for this use case?
   - At the subscription level
   - At the product level (across all subscriptions)
- **Token Quotas**: Should there be monthly/weekly token quotas?
- **Response Time Requirements**: Are there specific latency requirements?

### 7. PII Handling

- **PII Detection and Processing**: Does this use case involve sensitive personally identifiable information?
- **Anonymization Requirements**: Is PII anonymization needed for regulatory or privacy reasons?
- **Custom PII Patterns**: Are there industry-specific or organization-specific PII patterns that require detection?

### 8. Usage Tracking and Monitoring

- **Chargebacks**: Will this use case require internal chargebacks for AI usage?
- **Usage Metrics**: What metrics are needed for this specific use case?
- **Session/User Tracking**: Does this use case require tracking at the session or user level?

### 9. Error Handling

- **Throttling Strategy**: How should the system respond when capacity limits are reached?
- **Retry Policies**: What retry patterns make sense for this use case?

### 10. Product Naming Conventions

Having a consistent naming convention for APIM products is crucial for governance, especially in environments with multiple use cases, departments, and staging environments. The following considerations should guide your product naming strategy:

- **AI Service Type Prefix**: Prefix the product name with an abbreviation of the AI service type (e.g., "OAI-" for OpenAI, "AISRCH-" for AI Search)
- **Department/Team Identifier**: Include the business unit or team name in the product (e.g., "HR", "RETAIL", "FINANCE")
- **Use Case Type**: Indicate the primary purpose or capability (e.g., "ASSISTANT", "SEARCH", "AGENT")
- **Special Processing Indicator**: Add suffixes for special processing requirements (e.g., "PII" for products with PII handling)
- **Environment Designation**: For shared gateways across environments, include environment identifiers (e.g., "-DEV", "-TEST", "-PROD")

#### Example Product Naming Patterns:

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

## Decision Template for New Use Cases

When onboarding a new use case to the AI Hub Gateway, complete the following template to guide policy configuration:

```
# AI Gateway Use Case Onboarding Template

## Use Case Information
- Name: [Name of the use case]
- Description: [Brief description of the use case]
- Business Unit/Team: [Which team/department owns this use case]
- Contact Person: [Primary technical contact]

## Product Naming
- AI Service Prefix: [e.g., OAI for OpenAI, AISRCH for AI Search, MULTI for multi-service]
- Department/Team Code: [Short code for the business unit]
- Use Case Type: [e.g., ASSISTANT, SEARCH, AGENT, RAG]
- Special Processing Indicator: [e.g., PII, if applicable]
- Environment: [DEV, TEST, PROD, etc.]
- Proposed Product Name: [Following the convention, e.g., MULTI-HR-RAG-PII-PROD]

## Authentication and Security Requirements
- JWT Token Validation Required: [Yes/No]
- Entra ID Integration: [Yes/No]
- Tenant ID: [ID of the Microsoft Entra tenant to authorize]
- Client Application ID: [ID of the registered application that should be allowed]
- Audience Value: [Expected audience claim value in tokens]
- Additional Required Claims: [Any other claims that should be validated]

## Backend Access Requirements
- Allowed Backends: [List of allowed backend IDs, or "All"]
- Regional Restrictions: [Yes/No, if Yes - specify regions]

## Multi-Service AI Requirements
- Service Composition: [List all required services, e.g., "OpenAI GPT-4o, Azure AI Search, Document Intelligence"]
- Primary Service: [Which service is considered the primary/dominant one]
- Service Orchestration Method: [Client-side/Gateway-managed/Direct service-to-service]
- Cross-Service Authentication: [How authentication is handled across services]
- Usage Pattern: [e.g., "Sequential RAG (Search → LLM)", "Parallel processing", "Chain-of-thought"]

## Model Access Requirements
- Allowed Models: [List specific model deployments required]
- Model Families Required: [e.g., LLMs, Embedding models, image generation, etc.]
- Cross-Service Model Consistency: [Requirements for using consistent models across services]

## Content Safety Configuration
- Content Safety Required: [Yes/No]
- Categories to Monitor: [List categories and their thresholds, e.g., Hate: 4, Violence: 4]
- Shield Prompt: [True/False]
- Cross-Service Content Safety: [How to handle content safety across different services]
- Input/Output Filtering Requirements: [Which services need input/output filtering]

## Capacity Management
- Subscription-level Token Rate Limit (TPM): [e.g., 10000 tokens per minute]
- Product-level Total Token Rate Limit (TPM): [e.g., 15000 tokens per minute]
- Token Quota: [e.g., 100000 monthly]
- Token Quota Period: [Monthly/Weekly/Daily]
- Service-Specific Capacity Limits: [Any service-specific limitations]

## PII Processing Requirements
- PII Anonymization Required: [Yes/No]
- PII Detection Language: [en, auto, etc.]
- PII Confidence Threshold: [e.g., 0.75]
- PII Entity Category Exclusions: [List any PII categories to exclude]
- Custom PII Regular-Expressions Patterns: [List any custom regex patterns needed]
- Cross-Service PII Handling: [How PII is handled when data flows across services]

## Usage Tracking Requirements
- Chargeback Required: [Yes/No]
- Session/User Level Tracking: [Yes/No]
- Custom Dimensions Required: [List any additional tracking dimensions]
- Cross-Service Usage Attribution: [How to attribute usage across multiple services]

## Error Handling Strategy
- Retry-after Behavior: [How to handle retry-after headers]
- Throttling Response: [Custom message or standard]
- Service Dependency Failures: [How to handle when one service in the chain fails]
- Fallback Options: [Alternative paths when primary service is unavailable]

## Additional Requirements
- [Any other specific requirements for this use case]
```

## Understanding JWT Token Authentication with Microsoft Entra ID

For use cases requiring additional security beyond subscription keys, JWT token validation with Microsoft Entra ID (formerly Azure AD) provides a robust solution. This approach allows you to:

1. **Restrict access to specific client applications**: Only registered applications with the correct client ID can access the API
2. **Ensure tokens are properly issued**: Validates that tokens come from your trusted Entra ID tenant
3. **Verify appropriate permissions**: Checks that necessary scopes/roles are included in the token
4. **Implement Zero Trust principles**: Requires authentication at each access point, regardless of network location

### Implementation Requirements

To implement JWT token validation for your AI Hub Gateway use case, you need:

1. **Application Registration in Microsoft Entra ID**:
   - Register your client application in Entra ID to obtain a client ID
   - Define appropriate scopes or app roles for access control
   - Configure redirect URIs for authentication flows

2. **APIM Configuration**:
   - Set named values in APIM:
     - `entra-auth`: Set to "true" to enable validation
     - `tenant-id`: Your Microsoft Entra tenant ID
     - `audience`: The resource identifier that tokens should be issued for
     - `client-id`: The client ID of applications allowed to access the API

3. **Product Policy Implementation**:
   - Include the fragment that validates JWT tokens:
   ```xml
   <include-fragment fragment-id="aad-auth" />
   ```
   
4. **Client Requirements**:
   - Clients must acquire a valid token from Microsoft Entra ID
   - Include the token in the `Authorization` header using the `Bearer` scheme
   - Must still provide the subscription key for initial APIM authentication

### Security Considerations

- JWT tokens should be short-lived (1 hour or less)
- Consider requiring additional claims for more granular control
- Keep client secrets properly secured
- Implement appropriate CORS policies if browser clients will be accessing the API

## Example Use Cases

Below we demonstrate example use cases with different requirements and their corresponding APIM product policies:

### Example 1: HR Assistant with PII Processing

This use case requires comprehensive features including PII anonymization, content safety, and detailed capacity management.

#### Use Case Information
- Name: HR PII Assistant
- Description: Offering OpenAI services for internal HR platforms with PII anonymization processing
- Business Unit/Team: Human Resources
- Contact: HR Technology Team

#### Product Naming
- AI Service Prefix: OAI (OpenAI)
- Department/Team Code: HR
- Use Case Type: ASSISTANT
- Special Processing Indicator: PII
- Environment: PROD
- Product Name: OAI-HR-ASSISTANT-PII-PROD

#### Authentication and Security
- JWT Token Validation: Yes (required for sensitive HR data)
- Entra ID Integration: Yes
- Tenant ID: contoso.onmicrosoft.com (primary corporate tenant)
- Client Application ID: hr-employee-portal-app
- Audience Value: api://hr-assistant.contoso.com
- Additional Claims Required: groups (must contain 'HR-Employee-Portal-Users')

#### APIM Product Policy Configuration

```xml
<policies>
    <inbound>
        <base />

        <!-- Enable JWT token validation with Entra ID for secure access -->
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

        <!-- Capacity management - Subscription Level: allow only assigned tpm for each HR use case subscription -->
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
                
                <!-- Include the PII state saving fragment to push pii detection results to event hub -->
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

### Example 2: Retail Assistant with Basic Controls

This use case requires only basic model restrictions and capacity management, without the need for PII processing or advanced content safety.

#### Use Case Information
- Name: Retail Assistant
- Description: Offering OpenAI services for retail and e-commerce platforms assistant
- Business Unit/Team: Retail Operations
- Contact: Digital Store Team

#### Product Naming
- AI Service Prefix: OAI (OpenAI)
- Department/Team Code: RETAIL
- Use Case Type: ASSISTANT
- Special Processing Indicator: (None)
- Environment: PROD
- Product Name: OAI-RETAIL-ASSISTANT-PROD

#### Authentication and Security
- JWT Token Validation: No (standard subscription key only)
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
        <!-- Restrict access for this product to specific models -->
        <choose>
            <when condition="@(!new [] { "gpt-4o", "chat", "embedding" }.Contains(context.Request.MatchedParameters["deployment-id"] ?? String.Empty))">
                <return-response>
                    <set-status code="401" reason="Unauthorized model access" />
                </return-response>
            </when>
        </choose>

        <!-- Capacity management: allow only assigned tpm for each Retail use case subscritpion -->
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

### Example 3: Legal RAG with Multi-Service Integration

This example demonstrates a complex multi-service use case that combines OpenAI, Azure AI Search, and Document Intelligence.

#### Use Case Information
- Name: Legal Document RAG System
- Description: Multi-service solution for legal document analysis and Q&A using RAG pattern
- Business Unit/Team: Legal Department
- Contact: Legal Technology Team

#### Product Naming
- AI Service Prefix: MULTI (Multiple Services)
- Department/Team Code: LEGAL
- Use Case Type: RAG
- Special Processing Indicator: PII
- Environment: PROD
- Product Name: MULTI-LEGAL-RAG-PII-PROD

#### Multi-Service Requirements
- Service Composition: OpenAI GPT-4o, Azure AI Search, Document Intelligence
- Primary Service: OpenAI
- Service Orchestration: Gateway-managed orchestration
- Cross-Service Authentication: Consistent JWT across all services
- Usage Pattern: Sequential RAG (Document Intelligence → AI Search → GPT-4o)

#### Authentication and Security
- JWT Token Validation: Yes (required for sensitive legal data)
- Entra ID Integration: Yes
- Tenant ID: contoso.onmicrosoft.com
- Client Application ID: legal-document-system
- Audience Value: api://legal-rag.contoso.com
- Additional Claims Required: groups (must contain 'Legal-Document-Users')

#### APIM Product Policy Configuration

```xml
<policies>
    <inbound>
        <base />
        <!-- Enable JWT token validation with Entra ID for secure access across all services -->
        <include-fragment fragment-id="aad-auth" />

        <!-- Store the original URL for service routing -->
        <set-variable name="originalUrl" value="@(context.Request.Url.ToString())" />
        <set-variable name="serviceType" value="@{
            var url = context.Request.Url.ToString().ToLower();
            if (url.Contains("/openai/")) return "openai";
            if (url.Contains("/aisearch/")) return "aisearch";
            if (url.Contains("/documentintelligence/")) return "docint";
            return "unknown";
        }" />

        <!-- Service-specific configuration based on the detected service type -->
        <choose>
            <!-- OpenAI Service Configuration -->
            <when condition="@(context.Variables["serviceType"] == "openai")">
                <!-- Model restrictions for OpenAI -->
                <choose>
                    <when condition="@(!new [] { "gpt-4o", "embedding" }.Contains(context.Request.MatchedParameters["deployment-id"] ?? String.Empty))">
                        <return-response>
                            <set-status code="401" reason="Unauthorized model access" />
                        </return-response>
                    </when>
                </choose>
                
                <!-- Token limits for OpenAI -->
                <azure-openai-token-limit 
                    counter-key="@(context.Subscription.Id + "-openai")" 
                    tokens-per-minute="15000" 
                    estimate-prompt-tokens="false" 
                    tokens-consumed-header-name="consumed-tokens" 
                    remaining-tokens-header-name="remaining-tokens" 
                    token-quota="200000"
                    token-quota-period="Monthly"
                    retry-after-header-name="retry-after" />
                    
                <!-- Content safety for OpenAI -->
                <llm-content-safety backend-id="content-safety-backend" shield-prompt="true">
                    <categories output-type="EightSeverityLevels">
                        <category name="Hate" threshold="3" />
                        <category name="Violence" threshold="3" />
                        <category name="SelfHarm" threshold="3" />
                    </categories>
                </llm-content-safety>
                
                <!-- Backend selection for OpenAI -->
                <set-variable name="allowedBackend" value="openai-backend-0,openai-backend-1" />
            </when>
            
            <!-- AI Search Configuration -->
            <when condition="@(context.Variables["serviceType"] == "aisearch")">
                <!-- Configure AI Search specific policies -->
                <set-backend-service backend-id="aisearch-backend" />
                
                <!-- Rate limiting for AI Search -->
                <rate-limit calls="60" renewal-period="60" />
            </when>
            
            <!-- Document Intelligence Configuration -->
            <when condition="@(context.Variables["serviceType"] == "docint")">
                <!-- Configure Document Intelligence specific policies -->
                <set-backend-service backend-id="docint-backend" />
                
                <!-- Rate limiting for Document Intelligence -->
                <rate-limit calls="30" renewal-period="60" />
            </when>
            
            <otherwise>
                <return-response>
                    <set-status code="400" reason="Unsupported service type" />
                    <set-body>{"error": "The requested service is not supported by this product"}</set-body>
                </return-response>
            </otherwise>
        </choose>

        <!-- Common PII processing across all services -->
        <set-variable name="piiAnonymizationEnabled" value="true" />
        <choose>
            <when condition="@(context.Variables.GetValueOrDefault<string>("piiAnonymizationEnabled") == "true")">
                <!-- Configure PII detection settings -->
                <set-variable name="piiConfidenceThreshold" value="0.8" />
                <set-variable name="piiEntityCategoryExclusions" value="" />
                <set-variable name="piiDetectionLanguage" value="en" /> 
                
                <!-- Add legal-specific PII patterns -->
                <set-variable name="piiRegexPatterns" value="@{
                    var patterns = new JArray {
                        new JObject {
                            ["pattern"] = @"\b[A-Z]{2}\d{6}[A-Z]\b",
                            ["category"] = "CASE_NUMBER"
                        },
                        new JObject {
                            ["pattern"] = @"\bCASE[- ]?\d{2}[- ]?\d{4}\b",
                            ["category"] = "CASE_REFERENCE"
                        }
                    };
                    return patterns.ToString();
                }" />
                
                <set-variable name="piiInputContent" value="@(context.Request.Body.As<string>(preserveContent: true))" />
                <include-fragment fragment-id="pii-anonymization" />
                <set-body>@(context.Variables.GetValueOrDefault<string>("piiAnonymizedContent"))</set-body>
            </when>
        </choose>
        
        <!-- Cross-service usage tracking -->
        <set-header name="X-Service-Type" exists-action="override">
            <value>@(context.Variables["serviceType"])</value>
        </set-header>
        <set-header name="X-Multi-Service-Flow" exists-action="override">
            <value>MULTI-LEGAL-RAG</value>
        </set-header>
    
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        <!-- Service-specific response handling -->
        <set-variable name="responseBodyContent" value="@(context.Response.Body.As<string>(preserveContent: true))" />
        
        <!-- PII Deanonymization for all services -->
        <choose>
            <when condition="@(context.Variables.GetValueOrDefault<string>("piiAnonymizationEnabled") == "true" && 
                            context.Variables.ContainsKey("piiMappings"))">
                <set-variable name="piiDeanonymizeContentInput" value="@(context.Variables.GetValueOrDefault<string>("responseBodyContent"))" />
                <include-fragment fragment-id="pii-deanonymization" />
                <set-body>@(context.Variables.GetValueOrDefault<string>("piiDeanonymizedContentOutput"))</set-body>
            </when>
            <otherwise>
                <set-body>@(context.Variables.GetValueOrDefault<string>("responseBodyContent"))</set-body>
            </otherwise>
        </choose>
        
        <!-- Add usage tracking headers -->
        <set-header name="X-Service-Response-Time" exists-action="override">
            <value>@(context.Response.Headers.GetValueOrDefault("Duration", "0"))</value>
        </set-header>
    </outbound>
    <on-error>
        <base />
        <!-- Error handling with appropriate fallback -->
        <choose>
            <when condition="@(context.LastError.Source == "aisearch-backend")">
                <set-variable name="errorMessage" value="AI Search service is currently unavailable. Using fallback." />
                <set-header name="X-Error-Source" exists-action="override">
                    <value>AI Search</value>
                </set-header>
                <!-- Could implement fallback logic here -->
            </when>
            <when condition="@(context.LastError.Source == "docint-backend")">
                <set-variable name="errorMessage" value="Document Intelligence service is currently unavailable." />
                <set-header name="X-Error-Source" exists-action="override">
                    <value>Document Intelligence</value>
                </set-header>
            </when>
            <otherwise>
                <set-variable name="errorMessage" value="An error occurred in the gateway." />
            </otherwise>
        </choose>
        
        <set-header name="X-Error-Message" exists-action="override">
            <value>@(context.Variables.GetValueOrDefault<string>("errorMessage"))</value>
        </set-header>
    </on-error>
</policies>
```

## Decision Impact Analysis

The examples above demonstrate how different business requirements influence policy configuration:

### Features Comparison

| Feature | HR Assistant | Retail Assistant | Legal RAG System |
|---------|-------------|-----------------|------------------|
| Product Name | OAI-HR-ASSISTANT-PII-PROD | OAI-RETAIL-ASSISTANT-PROD | MULTI-LEGAL-RAG-PII-PROD |
| Service Composition | Single service (OpenAI) | Single service (OpenAI) | Multiple services (OpenAI, AI Search, Doc Intelligence) |
| Authentication | Subscription Key + JWT Token | Subscription Key only | Subscription Key + JWT Token |
| Entra ID Integration | Yes (tenant-specific) | No | Yes (tenant-specific) |
| Backend Restriction | Yes (specific region) | No (all regions) | Service-specific backends |
| Model Access Control | Limited to gpt-4o, embedding | More permissive | Service-specific controls |
| Content Safety | Advanced configuration | None | Applied to OpenAI services only |
| Token Rate Limits | Model-specific TPM | Single overall TPM | Service-specific rate limits |
| Token Quotas | Monthly quotas defined | None | Monthly quota for OpenAI only |
| PII Processing | Full anonymization & deanonymization | None | Cross-service PII handling |
| Service Orchestration | N/A | N/A | Gateway-managed with service routing |
| Error Handling | Basic | Basic | Advanced with service-specific fallbacks |

### Impact on System Architecture

1. **Authentication Complexity**: 
   - Single-service solutions can use simpler authentication schemes
   - Multi-service solutions require consistent authentication across all services

2. **Backend Load Distribution**: 
   - Multi-service scenarios need careful backend routing and load balancing
   - Service-specific backends may have different scaling characteristics

3. **Resource Consumption**: 
   - Multi-service scenarios have more complex policy processing
   - Cross-service orchestration adds gateway overhead

4. **Observability Requirements**: 
   - Multi-service solutions need end-to-end tracing
   - Service-specific performance metrics must be collected and correlated

5. **Compliance Impact**: 
   - PII handling across service boundaries requires special attention
   - Content safety may need to be applied differently for different service types

6. **Client Application Requirements**: 
   - Multi-service orchestration may simplify client implementation
   - Service-specific error handling may need to be exposed to clients

## Multi-Service AI Architecture Considerations

When implementing multi-service AI solutions through AI Hub Gateway, consider these architectural patterns:

### 1. Gateway-Orchestrated Pattern

The gateway handles service routing, coordination, and error handling:

```
Client → Gateway → [Service 1 → Service 2 → Service 3]
```

**Benefits:**
- Simplified client implementation
- Consistent policy enforcement
- Centralized observability
- Unified error handling

**Challenges:**
- Higher gateway processing overhead
- Complex policy configuration
- Potential bottlenecks

### 2. Client-Orchestrated Pattern

The client application coordinates multiple service calls:

```
Client → Gateway → Service 1
       ↓
Client → Gateway → Service 2
       ↓
Client → Gateway → Service 3
```

**Benefits:**
- More client control
- Lower gateway overhead
- Client-specific orchestration logic

**Challenges:**
- More complex client implementation
- Inconsistent handling across clients
- Distributed observability

### 3. Hybrid Orchestration Pattern

Some orchestration in gateway, some in client:

```
Client → Gateway → [Service 1 → Service 2]
       ↓
Client → Gateway → Service 3
```

**Benefits:**
- Balances control and simplicity
- Optimizes for common patterns
- Flexible implementation

**Challenges:**
- Clear responsibility boundaries needed
- Complex debugging across components

## Conclusion

Designing the right APIM Product policy for each AI use case requires balancing multiple factors including security, performance, compliance, and business needs. The decision template provided in this guide helps structure this decision-making process, with special attention to multi-service AI scenarios.

By reviewing the examples shown, teams can better understand how to configure policies that match their specific requirements. The single-service examples demonstrate focused controls, while the multi-service Legal RAG System example shows how to handle complex orchestration of multiple AI services under a unified governance model.

As organizations expand their use of generative AI, the integration of multiple AI services becomes increasingly common. Proper design of gateway policies for these complex scenarios ensures that organizations can leverage the full power of various AI services while maintaining consistent security, compliance, and operational controls.

Remember that these policies can be adjusted over time as needs evolve and usage patterns become more apparent. Regular reviews of product configurations are recommended to ensure they continue to meet business requirements and performance expectations.

## References

For more detailed guidance on specific aspects of AI Hub Gateway configuration and use cases, refer to these related guides:

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

### Advanced Scenarios
- [End-to-End Scenarios](./end-to-end-scenario.md) - Complete workflows implementing AI Hub Gateway
- [AI Hub Gateway Hybrid Deployment](./ai-hub-gateway-hybrid-deployment.md) - Deploying across hybrid environments
- [Bring Your Own Network](./bring-your-own-network.md) - Network integration options

### Multi-Service AI Guides
- [RAG Implementation Guide](./ai-hub-gateway-rag-implementation.md) - Building RAG solutions with multiple services
- [Multi-Service Orchestration](./multi-service-orchestration.md) - Patterns for orchestrating multiple AI services
- [Service Composition Best Practices](./service-composition-best-practices.md) - Best practices for combining AI services

### Troubleshooting
- [Deployment Troubleshooting](./deployment-troubleshooting.md) - Solutions for common deployment issues
- [OpenAI Onboarding](./openai-onboarding.md) - Guidance for onboarding new OpenAI models
