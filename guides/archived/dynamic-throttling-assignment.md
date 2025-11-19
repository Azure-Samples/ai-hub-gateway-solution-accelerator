# Gateway routing configurations

## Dynamic Throttling Assignment

Some times with reserved OpenAI models through PTU (provisioned throughput units), latency increases the closer you are getting to 100% utilization.

Although it is important to size correctly the capacity allocation for PTU, some occasional spikes can push the service to reach 90%+ utilization which results in increased latency.

In many cases, this is not a challenge, but in other cases where the use case is sensitive to latency this can potential impact the experience.

AI Hub Gateway routing engine offers a way to handle such events by falling back to other OpenAI instance to relief the primary PTU instance from being at maximum capacity.

Introducing ```Dynamic Throttling Assignment`` which is a routing strategy that allows you to define a target TPM that when it is reached, APIM will switch incoming traffic to backup OpenAI service temporary (by default for 30 seconds) allowing the PTU instance to regain capacity again then it will resume using it.

### Example

APIM, as part of AI Hub Gateway, is configured with 2 OpenAI services with a deployment called ptu-gpt4-o (notice primary PTU has priority 1 and PAYGO has priority 2)

An OpenAI deployment of gpt4-o has 50 PTU, which let's assume it can handle a 100K TPM (this is an estimate).

You can set a target of 80K TPM for that service, where APIM will use a rolling tokens-count against the deployment and automatically switch to the next priority OpenAI deployment once the target 80K TPM is reached.

In oder to leverage the dynamic throttling, you have to configure multiple points:

1. Add ```targetTPMLimit``` to the OpenAI backend routes (inbound policy section):

```csharp
// Notice targetTPMLimit is set to 500 TPM to guide APIM to switch suspend traffic to this backend
routes.Add(new JObject()
{
    { "name", "EastUS" },
    { "location", "eastus" },
    { "backend-id", "openai-backend-0" },
    { "priority", 1},
    { "targetTPMLimit", 500 },
    { "isThrottling", false }, 
    { "retryAfter", DateTime.MinValue } 
});
```

2. Setup a counter against the PTU deployment name for APIM to count the tokens (inbound policy section):

```xml

<!-- Dynamic Throttling Assignment TPM counters (work only if the backend/deployment is not throttling) -->
<choose>
    <when condition="@(context.Request.MatchedParameters["deployment-id"] == "chat" && ((JArray)context.Variables["routes"])[0]["isThrottling"].ToString() == "False")">
        <azure-openai-token-limit counter-key="openai-backend-0-chat" tokens-per-minute="1000000" estimate-prompt-tokens="true" tokens-consumed-variable-name="openai-backend-0-chat-ConsumedTokens" remaining-tokens-variable-name="openai-backend-0-chat-RemainingTokens" />
    </when>
</choose>

```

3. Reference ```dynamic-throttling-assignment``` policy fragment (outbound policy section):

```xml

<!-- Update Dynamic Priority Assignment based on TPM counters -->
<include-fragment fragment-id="dynamic-throttling-assignment" />

```

4. Test the policy updates through setting up a small ```targetTPMLimit``` and leverage APIM trace to notice that APIM is switching traffic after hitting the limit and switch it back once the counter goes below that target limit.

5. Run a load test against the service to ensure that the selected target limit is sufficient to manage latency within acceptable parameters and reduce the limit if it is not.

You can view a full APIM policy that is leveraging dynamic throttling policy [here](../infra/modules/apim/policies/openai_api_policy_dynamic_throttling.xml)