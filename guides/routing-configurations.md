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

```xml

```

You can view a full APIM policy that is leveraging dynamic throttling policy [here]()