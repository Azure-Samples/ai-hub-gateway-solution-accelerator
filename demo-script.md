# Updated Azure API Management demo guide

## Presenter pronunciation guide

These are approximate English pronunciations for terms used in the demo.

| Term               | Meaning                               | Say it aloud                                             |
| ------------------ | ------------------------------------- | -------------------------------------------------------- |
| API                | Application Programming Interface     | **ay-pee-eye**                                           |
| APIs               | Application Programming Interfaces    | **ay-pee-eyes**                                          |
| APIM               | Azure API Management                  | **ay-pim** or **ay-pee-eye-em**                          |
| APIOps             | API operations                        | **ay-pee-eye ops**                                       |
| JWT                | JSON Web Token                        | **jay-double-you-tee**; also commonly pronounced **jot** |
| REST               | Representational State Transfer       | **rest**                                                 |
| SOAP               | Simple Object Access Protocol         | **soap**                                                 |
| OpenAPI            | OpenAPI Specification                 | **open ay-pee-eye**                                      |
| GraphQL            | API query language                    | **graph cue-el**                                         |
| gRPC               | Remote procedure call framework       | **gee-are-pee-see**                                      |
| VS Code            | Visual Studio Code                    | **vee-ess code**                                         |
| XML                | Extensible Markup Language            | **ex-em-el**                                             |
| Microsoft Entra ID | Microsoft identity and access service | **Microsoft en-truh eye-dee**                            |
| DKK                | Danish krone currency code            | **dee-kay-kay**                                          |
| `ORD-1042`         | Demo order ID                         | **order ten forty-two**                                  |
| `CUST-4711`        | Demo customer ID                      | **customer forty-seven eleven**                          |
| `TM-IO`            | Demo product ID                       | **tee-em eye-oh**                                        |

---

## Environment readiness

This script is aligned with the deployed demo environment:

- API Management: `apim-dewmoejwc745e`
- Orders API base path: `/orders-demo`
- Products API base path: `/products-demo`
- Product: **Order Management APIs**
- API Center: `apic-dewmoejwc745e`
- Current Orders API revision: **Revision 1**
- Staged Orders API revision: **Revision 2**

The APIs are self-contained for a predictable presentation. APIM policies generate the demo responses, so no external Order Management backend is required.

The following items are not configured in this Developer-tier environment and must be described as optional capabilities rather than demonstrated live:

- JWT validation and Microsoft Entra ID sign-in for the developer portal
- The Commerce APIM workspace, because APIM Workspaces require Basic v2, Standard v2, Premium or Premium v2
- A prepared pull request and completed APIOps CLI extraction

---

## 1. Bring the Order API under management

**Show the imported Orders and Products APIs**

In the Azure portal, open your API Management instance and go to **APIs**.

Open the preconfigured APIs:

- `GET /orders/{orderId}` - retrieve an order
- `POST /orders` - create an order
- `GET /products/{productId}` - retrieve product information

The first two operations are in **Orders API**. The product operation is in **Products API**. Both were imported from the OpenAPI definitions stored in this repository.

Before selecting OpenAPI, briefly point out the other API options, including SOAP, GraphQL, WebSocket and gRPC. Don't configure them. The purpose is simply to show that APIM isn't limited to REST APIs.

After importing, open the API and briefly show its operations.

For the demo, use an order such as ORD-1042 throughout.

> Let's imagine this is an existing Order Management API. It could already be running in Azure or somewhere else. For this demo, APIM generates deterministic responses so the presentation doesn't depend on an external backend.
>
> I'm importing the existing API definition and putting a managed API surface in front of it.
>
> And although I'm using a REST API for the demo, this isn't exclusively a REST API platform. The same API Management platform can be used across other API styles such as GraphQL, WebSocket and gRPC.

---

## 2. Establish the baseline

**Test the Order API**

Open:

`GET /orders-demo/orders/{orderId}`

Use:

`ORD-1042`

Send the request through the built-in test experience.

Have the backend return something recognisable, for example:

```yaml
orderId: ORD-1042
customerId: CUST-4711
productId: TM-IO
quantity: 2
currency: DKK
status: Confirmed
```

Don't introduce any policies yet. The objective is simply to establish that the API is working through APIM.

> Before changing anything, let's make sure our API actually works.
>
> I'm sending a request through the API Management gateway to retrieve order ORD-1042.
>
> The request goes through the gateway and we get our predictable demo order back.
>
> That's our baseline. Now we can start changing how the API behaves centrally in API Management.

---

## 3. Add a caching policy

**Cache product information**

Use:

`GET /products-demo/products/TM-IO`

Send it once and point out the `X-Cache: MISS` response header.

Show the preconfigured caching policy. It stores product data for 60 seconds.

Send the same request again within 60 seconds and point out `X-Cache: HIT`.

Use the Product endpoint rather than the Order endpoint because product information makes the caching scenario much easier to explain.

> We probably don't want to cache everything.
>
> Order status can change, so caching that blindly wouldn't necessarily make sense.
>
> But imagine product information is read extremely frequently and changes much less often.
>
> Instead of every consumer request travelling all the way to the product backend, we can introduce caching here at the gateway.
>
> The interesting thing is that I haven't changed the Product application. We've introduced this behaviour centrally through API Management.

---

## 4. Explain protection for order creation

**Describe JWT validation as an optional extension**

Move to:

`POST /orders-demo/orders`

This environment does not have an Entra app registration or JWT policy configured. Do not attempt the unauthenticated/authenticated JWT comparison in this demo.

Instead, explain where a `validate-jwt` policy would run before request validation. The APIM product still requires a subscription key, so gateway access is not anonymous.

> Reading information is one thing. Creating an order is something we definitely want to protect.
>
> In a production setup, rather than every backend independently implementing our API perimeter controls, we can apply authentication and authorisation requirements at the gateway.
>
> This demo uses a subscription key. The same API can be extended with Microsoft Entra ID and JWT validation when the identity application is configured.

---

## 5. Protect backend credentials

**Show a named value backed by Azure Key Vault**

Open **Named values**.

Open `order-backend-api-key`.

Show that it is secret and references the `order-backend-api-key` secret in `kv-dewmoejwc745e` without revealing the value.

Return to the Orders API policy and show `{{order-backend-api-key}}` in the `x-order-backend-key` header policy.

Don't reveal the actual credential during the demo.

> The gateway itself may need credentials or configuration to communicate with backend systems.
>
> What I don't want is somebody putting those credentials directly into an API policy.
>
> Here we're referencing configuration through a named value, and sensitive values can be backed by Azure Key Vault.
>
> That lets the policy use the secret without us embedding the actual secret into the policy.

---

## 6. Reject malformed orders

**Validate a request against the API contract**

Keep using:

`POST /orders-demo/orders`

First send a valid request.

Then deliberately send an invalid order.

For example, remove a property that your OpenAPI schema defines as required.

For this environment, submit `quantity: -5`. The OpenAPI schema defines a minimum quantity of 1, making the failure predictable.

The important thing is that the invalid condition must actually be represented in your OpenAPI schema so that the demo produces a predictable validation failure.

Show the validate-content policy.

Send the malformed request and show that APIM rejects it.

> This request is authenticated, so we know who is making it. But that doesn't necessarily mean the request itself is valid.
>
> Here we've received an order that doesn't conform to the contract we've defined.
>
> Rather than allowing malformed data to travel further into our architecture, API Management can validate the request and reject it at the gateway.
>
> So we're protecting not only access to the backend but also the contract that the backend expects.

---

## 7. Move from the portal into the developer workflow

**Open the API in VS Code**

Switch to VS Code and open the Azure API Management extension.

Expand the APIM instance and locate the Order API that you've been demonstrating.

Show the API and its policies.

> This is where I want to switch personas slightly.
>
> I've intentionally been using the Azure portal so we could see what's happening.
>
> But developers don't necessarily want their entire API development workflow to be portal driven.
>
> We can bring API Management into the developer environment as well.

---

## 8. Work with policies in VS Code

**Edit and debug the Order API policy**

Open one of the policies you've just demonstrated in VS Code.

Caching or request validation works well because the audience already understands what the policy does.

Show the policy editing experience.

Then demonstrate or point out the current policy assistance and debugging experience, including GitHub Copilot for Azure assistance where available.

Don't write a complicated policy from scratch.

> We've deliberately used fairly simple policies so far, but real API policies can become much more sophisticated.
>
> Once we're working with larger policies, I'd much rather bring those into my normal developer workflow.
>
> Here I can work with the policy in VS Code, understand what it's doing and debug it.
>
> And if this happens to be a policy written by another team, I can also use Copilot assistance to help me understand what the existing policy actually does.

---

## 9. Safely change the Order API

**Create Revision 2**

Return to the Azure portal.

Show Revision 1 as the currently published Order API.

Revision 2 is already staged. Select it from the revision picker.

For the demonstration, make a simple non-breaking change.

Revision 1 might return:

```yaml
orderId: ORD-1042
status: Confirmed
```

Test Revision 2 directly with:

`GET /orders-demo;rev=2/orders/ORD-1042`

Revision 2 exposes an additional field:

```yaml
estimatedDelivery: 2026-09-21
```

Test Revision 2 before making it current.

> The business now wants us to expose estimated delivery information to applications consuming the Order API.
>
> I don't necessarily want to immediately modify what every existing consumer sees.
>
> Instead, I can create a revision and make the change there.
>
> Now I can test Revision 2 independently while Revision 1 remains the current API.

---

## 10. Explain revisions versus versions

**Use the Order API to explain the lifecycle**

Stay on the revisions experience.

Don't create an entirely new version unless someone specifically asks to see it.

Use the estimated-delivery example to explain that this is a small non-breaking evolution of the API.

Then contrast that with a hypothetical breaking change.

> For this particular change, I'm simply adding information. That's a good example of safely iterating using a revision.
>
> If instead I wanted to introduce a breaking contract that consumers had to deliberately migrate to, that's where I'd start thinking about API versions.
>
> So versions and revisions solve related but different lifecycle problems.

---

## 11. Promote the revision

**Make Revision 2 current**

After successfully testing the new response, make Revision 2 current.

Test:

`GET /orders-demo/orders/ORD-1042`

again and show estimatedDelivery in the current response.

> We've tested the change without disturbing our consumers.
>
> Now that we're satisfied with it, I can make the revision current.
>
> So we've gone through a controlled API lifecycle rather than modifying our live API and simply hoping everything continues to work.

---

## 12. Turn APIs into a consumable product

**Show the Order Management APIs product**

Open **Products**.

Have a product prepared called:

**Order Management APIs**

Include:

- Orders API
- Products API

Show how APIs are packaged into the product and briefly show its access/subscription configuration.

> So far we've mostly looked at the producer side.
>
> But APIs only create value when another team can actually find and consume them.
>
> Here we've packaged our Order and Product APIs together as an Order Management API product.

---

## 13. Become the API consumer

**Tour the developer portal**

Open a pre-published developer portal rather than customising the portal live.

Now deliberately change persona.

Pretend that you are a developer building an application that needs order information.

Find **Order Management APIs**.

Open the Orders API.

Show:

- API discovery
- Documentation
- `GET /orders/{orderId}`
- Access/subscription experience
- Testing the API

Use ORD-1042 again if possible.

> For the last part of the demo I was the API provider.
>
> Now I'm going to become an API consumer.
>
> Imagine I'm developing a new application and I need access to order information.
>
> Rather than finding the right team, asking somebody for a Swagger file and then trying to understand how I'm supposed to authenticate, I can discover the available API product through the developer portal.
>
> I can understand the contract, see the available operations, get access and start experimenting with the API through a self-service experience.

---

## 14. Show identity for the developer experience

**Show Microsoft Entra ID integration**

This environment does not have a Microsoft Entra ID identity provider configured for the developer portal. Describe the capability without opening the identity provider configuration.

> We also don't need to create another separate identity system just because we're publishing APIs.
>
> The developer experience can integrate with Microsoft Entra ID, allowing the organisation's existing identity environment to be part of the API consumption experience. That identity setup is intentionally outside today's self-contained demo.

---

## 15. Explain scaling from one API team to many

**Describe the Commerce workspace as a tier-dependent option**

Do not open **Workspaces** in this environment. The APIM service uses the Developer SKU, which does not support Workspaces.

Use the architecture slide to describe a hypothetical **Commerce APIs** workspace containing the Orders API, Products API and Order Management APIs product. Explain that a live workspace demonstration requires Basic v2, Standard v2, Premium or Premium v2.

> The example we've been working through is manageable when there's one API and one team.
>
> But now imagine we have a Commerce team, a Customer team, a Logistics team and many others all building APIs.
>
> A purely centralised operating model quickly becomes difficult.
>
> On a supported APIM tier, Workspaces let us move towards federated API management.
>
> The platform team provides the shared API Management platform and central governance, while individual API teams can have scoped ownership of their API resources.
>
> So we don't necessarily have to choose between central governance and team autonomy. We can design for both.

---

## 16. Zoom out to the wider API estate

**Open Azure API Center**

Move from API Management to Azure API Center.

Have several APIs registered so it looks like an actual API estate rather than a catalogue containing only your demo API.

The deployed API Center inventory includes the Orders and Products APIs alongside AI, Weather and MCP APIs. Open:

- Orders API
- Products API

Search for or open the **Orders API**.

Show its available metadata, versions, definitions and deployments where configured.

> We've been zoomed in on one Order API running through API Management.
>
> Now let's zoom out.
>
> In a real organisation, there may be APIs across different teams, platforms and environments, and they won't necessarily all be behind this particular API Management gateway.
>
> API Center gives us the broader inventory and design-time governance view of that API estate.
>
> Now I can discover that the Orders API exists, understand its definition and see information associated with its lifecycle.

---

## 17. Show API Center and API Management together

**Show the Orders API in both worlds**

If configured, show that your APIM service has been linked with API Center and show the Orders API in the API Center inventory.

Use this to explicitly explain the distinction.

> API Center and API Management aren't competing ways of doing the same thing.
>
> API Management is where we're managing API runtime concerns: gateway traffic, security, policies and observability.
>
> API Center gives us the broader design-time inventory and governance perspective.
>
> Used together, we get both the runtime platform and visibility across the wider API estate.

---

## 18. Observe the traffic you generated

**Open Azure Monitor/Application Insights**

Before the session, generate some traffic.

During the demo itself, you've also naturally generated requests as part of the story.

Ideally have examples resembling:

- `GET /orders-demo/orders/ORD-1042` → success
- `GET /products-demo/products/TM-IO` → success
- `POST /orders-demo/orders` containing malformed content → rejected
- `POST /orders-demo/orders` containing valid content → success

Optionally request an unknown order to create a not-found response.

Do not describe a 401 as a JWT rejection in this environment. JWT validation is not configured.

Open your monitoring experience and show the resulting API traffic, metrics and logs.

> The nice thing about this part of the demo is that we're now looking at the requests we've actually been generating.
>
> We've had successful requests, we've deliberately sent malformed requests and we've had authentication failures.
>
> Because those requests are flowing through the gateway, API Management becomes an important observation point for what's happening across the APIs.

---

## 19. Investigate a failed request

**Show troubleshooting telemetry**

Select one of the failed requests if your monitoring setup makes this easy to demonstrate.

Show the relevant gateway telemetry or Application Insights/Azure Monitor information.

> For an operations team, I'm generally less interested in whether a product has a dashboard and much more interested in whether I can answer a practical question:
>
> What happened to this request, and why?
>
> The API platform becomes part of the operational model as well as the development and governance model.

---

## 20. Put the Order API configuration into Git

**Show the configuration repository**

Switch to GitHub or Azure DevOps.

Open the APIM configuration already stored in this repository.

Open the Order API artefacts and show recognisable things from earlier in the demo, particularly:

- `bicep/infra/modules/apim/order-demo/orders-api-v1.openapi.yaml`
- `bicep/infra/modules/apim/order-demo/orders-v1-policy.xml`
- `bicep/infra/modules/apim/order-demo/products-policy.xml`
- `bicep/infra/modules/apim/order-demo.bicep`

The audience should recognise that these are the same things you've been configuring through APIM.

> Everything I've shown so far works nicely interactively.
>
> But if the only way we operated a large enterprise API platform was by making changes manually in the Azure portal, we'd eventually create an operational problem.
>
> So this is where we move into APIOps.

---

## 21. Show configuration-as-code

**Show the APIM configuration in the repository**

Explain that the OpenAPI definitions, policies and Bicep resources are stored in Git and deployed through automation.

Mention APIOps CLI as an additional extraction/publishing workflow, but do not claim that the current files were extracted with APIOps CLI.

> Instead of treating API Management configuration as something that only exists inside the Azure resource, we can represent that configuration as artefacts and manage it through Git. APIOps CLI is another option for extracting and publishing APIM configuration.
>
> Now API definitions and API Management configuration can participate in the same engineering practices as the applications using them.

---

## 22. Make an API change through a pull request

**Show a prepared Order API pull request if one has been created**

This repository now contains the API artefacts, but a demonstration pull request is not created automatically. Prepare one before the presentation if this section will be shown.

For example:

- Change the cache configuration for the Product API
- Modify a policy
- Update the Order API definition
- Add the estimatedDelivery contract change you demonstrated earlier

Show the diff.

Don't merge it live.

> Remember the change we made earlier to our Order API?
>
> Now instead of somebody making that change manually in our production environment, it's an engineering change.
>
> We can see exactly what changed.
>
> Someone else can review it.
>
> We retain the history.
>
> And importantly, we can review and preview the change before it's published.

---

## 23. Show the APIOps deployment workflow

**Show GitHub Actions or Azure Pipelines**

Open the existing deployment workflow and show how approved APIM configuration can move from source control towards the API Management environment.

The repository includes `.azdo/pipelines/azure-dev.yml`, which provisions the Bicep configuration through `azd provision`.

Don't trigger a full deployment unless you've specifically designed the demo to make that safe and predictable.

> Once this change has gone through the engineering process, automation can publish the approved configuration into API Management.
>
> And that's an important distinction in the way I'd think about the Azure portal.
>
> The portal is extremely useful for understanding, exploring and troubleshooting the platform.
>
> But when we're operating this at enterprise scale, Git and automation become part of our operating model.

---

## 24. Close on the complete Order-to-Cash story

**Return to the architecture slide**

Don't finish the demo looking at XML, a pipeline or the Azure portal.

Return to your Order-to-Cash / Azure Integration Services architecture visual.

Trace the story you have just demonstrated:

**Order backend**

↓

**Order API**

↓

**API Management**

↓

**Authenticate → Validate → Govern → Observe**

↓

**Order Management API product**

↓

**Developer/consumer**

Then zoom outward:

**Commerce workspace on a supported tier** → delegated team ownership

**API Center** → enterprise API inventory and governance

**APIOps** → source control, review and automated publishing

> We started with something very simple: an Order API that already existed.
>
> We brought it under management without rewriting the backend.
>
> We secured it, validated requests, introduced gateway behaviour such as caching and evolved the API safely through revisions.
>
> Then we switched perspective and looked at how another developer could discover and consume that API.
>
> As we scaled the scenario beyond a single team, we introduced workspaces for federated API management and API Center to give us visibility across the wider API estate.
>
> We then looked at the requests flowing through the platform from an operational perspective.
>
> And finally, we took the configuration we'd been working with interactively and moved it into an engineering workflow using Git and APIOps.
>
> So the story isn't really about an API gateway anymore.
>
> It's about the lifecycle around the API:
>
> **Discover. Import. Protect. Test. Develop. Change. Publish. Federate. Observe. Automate.**
>
> And all of that started with the same Order API.