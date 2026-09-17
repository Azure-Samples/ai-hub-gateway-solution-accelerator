# Order API demo readiness

The optional Order API demo deploys a self-contained set of API Management assets for the Order-to-Cash presentation. Enable it with:

```powershell
azd env set ENABLE_ORDER_API_DEMO true
azd provision
```

The demo uses APIM policy-generated responses so it does not depend on an external Order Management backend.

## Provisioned assets

| Demo capability | Provisioned asset |
| --- | --- |
| Import and test an API | `Orders API` with `GET /orders/{orderId}` and `POST /orders` |
| Cache product information | `Products API` with `GET /products/{productId}` and a 60-second APIM cache |
| Protect backend credentials | Key Vault secret and APIM named value named `order-backend-api-key` |
| Validate malformed orders | `validate-content` against the OpenAPI request schema |
| Revisions | Current revision 1 and staged revision 2 with `estimatedDelivery` |
| Product and subscriptions | Published `Order Management APIs` product containing both APIs |
| Developer portal | A new current portal revision is published after the product is provisioned |
| Monitoring | Azure Monitor and Application Insights diagnostics at 100% sampling |
| API Center | Orders and Products registrations, definitions, versions, and APIM deployments |
| APIOps source | OpenAPI definitions, policies, and Bicep resources in this repository |

## Presenter endpoints

Use an APIM subscription key with these requests:

| Scenario | Request | Expected result |
| --- | --- | --- |
| Retrieve the demo order | `GET /orders-demo/orders/ORD-1042` | `200`, status `Confirmed` |
| Generate a not-found trace | `GET /orders-demo/orders/UNKNOWN` | `404` |
| Establish the product cache | `GET /products-demo/products/TM-IO` | `200`, `X-Cache: MISS` |
| Demonstrate the cache | Repeat the product request within 60 seconds | `200`, `X-Cache: HIT` |
| Create a valid order | `POST /orders-demo/orders` with the OpenAPI example body | `201` |
| Reject malformed content | Omit `currency` or submit `quantity: -5` | `400` from `validate-content` |
| Test staged revision 2 | `GET /orders-demo;rev=2/orders/ORD-1042` | `200` with `estimatedDelivery` |

Revision 1 remains current until revision 2 is promoted in the portal. Promoting revision 2 during the presentation creates the intended public lifecycle change.

## Environment-specific exclusions

These capabilities require presenter-specific identity or service-tier decisions and are not enabled by `ENABLE_ORDER_API_DEMO`:

- **JWT validation and Microsoft Entra developer portal sign-in** require an Entra app registration and client credential.
- **APIM Workspaces** require Basic v2, Standard v2, Premium, or Premium v2. A Developer-tier service cannot host the Commerce workspace.
- **VS Code extensions and Copilot assistance** must be installed on the presenter workstation.
- **Pull requests and APIOps deployment runs** should be prepared in the presenter's Git hosting environment. The repository contains the deployment pipeline and the demo API configuration, but does not create a pull request automatically.
