# Standalone central private DNS

Deploy this folder **manually**, independently of the accelerator. It is not called by the accelerator's [main template](../main.bicep), `azd`, or its deployment pipeline.

The resource-group-scoped [main.bicep](./main.bicep) deploys private DNS zones into an existing dedicated resource group. Create the resource group first with `az group create`, then provision the zones with `az deployment group create`. Optional resolution-only VNet links are managed by this deployment as well. It does not create resource groups, VNets, private endpoints, DNS resolvers, forwarding rules, or application resources. Private endpoint DNS zone groups in the accelerator populate DNS records.

## Prerequisites

- Azure CLI with Bicep installed (`az bicep version`).
- Permission to create the DNS resource group in the central DNS subscription, or have a platform administrator create it ahead of time.
- Permission to create deployments and manage private DNS zones and links in that resource group (for example, Contributor scoped to the DNS resource group). The Bicep deployment itself does not require subscription-scoped deployment permissions.
- When adding links, permission for `Microsoft.Network/virtualNetworks/join/action` on each target VNet, including VNets in another resource group or subscription.
- The identity deploying the accelerator needs access to attach its private endpoint DNS zone groups to these zones (including `Microsoft.Network/privateDnsZones/join/action`; Private DNS Zone Contributor is a built-in option on the DNS resource group), in addition to its normal accelerator permissions.
- Register `Microsoft.Network` in the relevant subscriptions. Cross-subscription DNS and VNet resources must be accessible to the deploying identity in the same Microsoft Entra tenant.

These zone names target Azure public cloud. Do not create another copy of a zone already centrally managed for the same clients; use its existing ID instead.

## Zones and output keys

All 16 zones are provisioned so the output covers the accelerator's base and optional private endpoints, plus Azure Container Registry and Azure AI Search for the larger AI Gateway + Agents landing zone.

| `existingPrivateDnsZones` key | Zone |
|---|---|
| `openai` | `privatelink.openai.azure.com` |
| `keyVault` | `privatelink.vaultcore.azure.net` |
| `monitor` | `privatelink.monitor.azure.com` |
| `eventHub` | `privatelink.servicebus.windows.net` |
| `cosmosDb` | `privatelink.documents.azure.com` |
| `storageBlob` | `privatelink.blob.core.windows.net` |
| `storageFile` | `privatelink.file.core.windows.net` |
| `storageTable` | `privatelink.table.core.windows.net` |
| `storageQueue` | `privatelink.queue.core.windows.net` |
| `cognitiveServices` | `privatelink.cognitiveservices.azure.com` |
| `apimGateway` | `privatelink.azure-api.net` |
| `aiServices` | `privatelink.services.ai.azure.com` |
| `redis` | `privatelink.redis.azure.net` |
| `logicApp` | `privatelink.azurewebsites.net` |
| `containerRegistry` | `privatelink.azurecr.io` |
| `aiSearch` | `privatelink.search.windows.net` |

The original 14 keys match the current accelerator DNS inputs. The additional `containerRegistry` and `aiSearch` keys are available to landing-zone deployments; the accelerator accepts the full object but does not consume these two keys or provision their private endpoints. Configure those services' private endpoint DNS zone groups to reference the corresponding IDs. All 16 zones receive links to the VNets supplied in `virtualNetworkIds`.

The `monitor` zone alone is not a complete Azure Monitor Private Link DNS design; if enabling Azure Monitor Private Link Scope, also review its [additional required zones and DNS configuration](https://learn.microsoft.com/azure/azure-monitor/fundamentals/azure-monitor-network-access).

## 1. Configure and deploy the DNS resource group and zones

Run the following PowerShell commands from the **repository root**. Set the DNS subscription, dedicated resource group name, and resource group region in the CLI variables below. Edit [main.bicepparam](./main.bicepparam) with zone/link tags and any **already existing** VNet IDs. For a new accelerator VNet, leave `virtualNetworkIds = []` initially.

```powershell
az login
$dnsSubscriptionId = '<central-dns-subscription-id>'
$dnsResourceGroup = 'rg-dns-zones'
$resourceGroupLocation = 'swedencentral'
$deploymentName = 'citadel-central-dns'

az account set --subscription $dnsSubscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Unable to select the central DNS subscription.' }

az group create `
  --subscription $dnsSubscriptionId `
  --name $dnsResourceGroup `
  --location $resourceGroupLocation `
  --tags managed-by=citadel-central-dns
if ($LASTEXITCODE -ne 0) { throw 'Central DNS resource group creation failed.' }

az deployment group create `
  --subscription $dnsSubscriptionId `
  --resource-group $dnsResourceGroup `
  --name $deploymentName `
  --parameters .\bicep\infra\central-dns\main.bicepparam
if ($LASTEXITCODE -ne 0) { throw 'Central DNS deployment failed.' }
```

**Resource group creation is a separate CLI step**, not part of Bicep. Skip `az group create` if the dedicated group already exists. The `--resource-group` argument selects where zones and links are deployed; there are no resource group name or location parameters in Bicep. Zones and links are global, regardless of the resource group's region. Resource group tags are managed by the CLI step; the Bicep `tags` parameter applies only to zones and links.

Optionally preview the DNS changes before deployment:

```powershell
az deployment group what-if `
  --subscription $dnsSubscriptionId `
  --resource-group $dnsResourceGroup `
  --name $deploymentName `
  --parameters .\bicep\infra\central-dns\main.bicepparam
if ($LASTEXITCODE -ne 0) { throw 'Central DNS what-if failed.' }
```

## 2. Pass the deployment output to the accelerator

Export just the zone ID object, not the entire deployment output envelope:

```powershell
$zoneJson = az deployment group show `
  --subscription $dnsSubscriptionId `
  --resource-group $dnsResourceGroup `
  --name $deploymentName `
  --query properties.outputs.existingPrivateDnsZones.value `
  --output json
if ($LASTEXITCODE -ne 0) { throw 'Unable to read central DNS zone IDs.' }
if (-not $zoneJson) { throw 'Central DNS zone ID output is empty.' }

$zoneIds = ($zoneJson -join "`n") | ConvertFrom-Json
if (@($zoneIds.PSObject.Properties).Count -ne 16) { throw 'Expected all 16 central DNS zone IDs.' }
$zoneIds | ConvertTo-Json | Set-Content -Encoding utf8 .\bicep\infra\central-dns-zones.json
```

In the accelerator's [main.bicepparam](../main.bicepparam), **replace** the existing `param existingPrivateDnsZones = { ... }` block with:

```bicep
param existingPrivateDnsZones = loadJsonContent('./central-dns-zones.json')
```

Alternatively, paste the IDs directly into that parameter object, or set the existing `EXISTING_DNS_ZONE_*` environment variables used by the shipped parameter file. The file-based approach above does not require setting those environment variables. `dnsZoneRG` and `dnsSubscriptionId` can remain empty when using explicit IDs.

Deploy the accelerator using its normal workflow and the **accelerator subscription**, which can differ from the DNS subscription. Explicit IDs work with both `useExistingVnet = true` and `false`. With a new VNet, the accelerator skips creation and local linking of zones for which IDs are supplied; without explicit IDs, its existing local DNS behavior is unchanged.

## 3. Link the accelerator VNet

Passing zone IDs configures private endpoint DNS zone groups; **it does not establish DNS resolution from a VNet**.

- **Existing VNet:** add its full resource ID to `virtualNetworkIds` before step 1.
- **New VNet:** create the zones first, pass their IDs into the accelerator, deploy the accelerator, then add its VNet ID to [main.bicepparam](./main.bicepparam) here and repeat the central DNS what-if and deployment commands in step 1.

```bicep
param virtualNetworkIds = [
  '/subscriptions/<accelerator-subscription-id>/resourceGroups/<network-resource-group>/providers/Microsoft.Network/virtualNetworks/<accelerator-vnet-name>'
]
```

Links are stored under the central zones, with auto-registration disabled and deterministic names. Retain the full list of desired VNet IDs on redeployment. Removing an ID from the parameter does not delete a previously deployed link in incremental mode; remove obsolete links explicitly after reviewing their consumers. If a link already exists under another name, reuse that link by omitting the VNet here rather than attempting to create a second link.

For Azure-provided DNS, link each consuming VNet. With custom DNS or on-premises clients, configure forwarding through your existing Azure DNS Private Resolver or DNS forwarder; VNet peering alone does not provide private-zone resolution. This deployment does not alter VNet DNS server settings. Ensure resolution is configured **before running workloads or validation notebooks**.

For an existing accelerator that already owns local zones, changing the IDs does not delete those zones or their VNet links in incremental mode. Plan a migration window: verify the private endpoint zone groups and central records, then remove the conflicting local-zone VNet links before adding central-zone links. Azure does not allow linking the same VNet to two zones with the same name. Do not delete shared zones or links without checking their other consumers.

## Verify

Offline regression tests require Bicep CLI 0.41.2 or newer and an Azure CLI version with `az bicep snapshot`. They do not deploy resources:

```powershell
& .\bicep\infra\central-dns\tests\test-central-dns.ps1
```

After deployment, inspect the zones and links:

```powershell
$dnsResourceGroup = 'rg-dns-zones' # Match the group selected in step 1.
az network private-dns zone list --subscription $dnsSubscriptionId --resource-group $dnsResourceGroup --query "[].name" --output table
az network private-dns link vnet list --subscription $dnsSubscriptionId --resource-group $dnsResourceGroup --zone-name privatelink.openai.azure.com --output table
```

From a host using the linked VNet's DNS path, resolve an actual accelerator service hostname, for example `Resolve-DnsName '<foundry-account-name>.openai.azure.com'`, and verify that it returns the expected private endpoint IP. Repeat for the enabled services.

## Lifecycle and outputs

- `resourceGroupId`: dedicated DNS resource group ID.
- `existingPrivateDnsZones`: accelerator-compatible zone ID object, including `containerRegistry` and `aiSearch` for other landing-zone deployments.
- `privateDnsZoneIds`: flat array, also suitable for the optional [developer VPN](../developer-vpn/README.md) deployment.

DNS provisioning, VNet links, RBAC, and DNS forwarding remain a separate platform responsibility. Deleting the accelerator resource group does not delete the central zones or links owned here. Private endpoint deletion can remove its managed DNS records. Do not delete the central DNS resource group while any accelerator or other consumer still depends on it. Azure Private DNS charges apply independently.

References: [resource-group-scoped Bicep deployments](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-resource-group), [private endpoint DNS integration](https://learn.microsoft.com/azure/private-link/private-endpoint-dns-integration).
