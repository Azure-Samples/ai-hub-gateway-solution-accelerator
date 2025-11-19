# Bring your own network

This guide will walkthrough how to bring your own network to the platform.

As everything in the accelerator deployment is using virtual networks, it becomes a critical part for adopting it as part of an existing network.

Keep in mind, that this accelerator is designed to be self-contained, which means if you wish for the script to provision everything needed end-to-end it is possible and it is the default behavior. However, if you wish to bring your own network, you can do so by following the steps below.

## Prerequisites

- All network resources must belong to the same subscription (except for private DNS zones which may exist in a different subscription).
- Virtual network must be configured fully with the required subnets (details are below)
- Private endpoints relies to Azure Private DNS Zones, which they must be configured and connected to the DNS resolver of the virtual network.
- [main.bicep](../infra/main.bicep) must be updated to reflect the existing network configurations (detailed later in the guide).
- APIM in internal network mode requires DNS resolution to be configured. The following are options you may need to consider:
    - APIM Custom Domains (recommended): implement custom domains for APIM endpoints (like Gateway, Management and Portal) and make sure that the network DNS resolver can resolve them to the APIM private IP addresses.
        - This will require a custom domain TLS certificate to be used for the APIM endpoints and you can use wild card CA issued certificate for a subdomain (like *.api.az.somecompany.com).
    - Azure Private DNS Zones: create a private DNS zone for the APIM endpoints and configure the virtual network to use it.
        - As APIM is using 5 different endpoints (Gateway, Management, Portal, Developer and SCM), you need to create 5 different DNS records in the private DNS zone in azure-api.net private zone
        - This would be problematic if you have external APIM relying on public DNS as it will no longer be resolver as you integrate this is. One work around is to add to the private zone the public IP records for the external APIM endpoints that you may have.

## Updating the [main.bicep](../infra/main.bicep) file

The main.bicep file is the entry point for the deployment. It contains all the resources that will be deployed to the Azure subscription.

Below is the areas that you need to update if you are bringing an existing network in the same subscription but in a different resource group:

```bicep
//Networking - VNet
param useExistingVnet bool = true
param existingVnetRG string = 'REPLACE-WITH-EXISTING-VNET-RG'
param vnetName string = 'REPLACE-WITH-EXISTING-VNET-NAME'
param apimSubnetName string = 'REPLACE-WITH-EXISTING-APIM-SUBNET-NAME'
param privateEndpointSubnetName string = 'REPLACE-WITH-EXISTING-PRIVATE-ENDPOINT-SUBNET-NAME'
param functionAppSubnetName string = 'REPLACE-WITH-EXISTING-FUNCTION-APP-SUBNET-NAME'

// Networking - Private DNS
// Leave empty if you want the script to create the private zones, but will not associate them with the selected virtual network (you need to do that manually or integrate with hub vnet DNS resolver)
param dnsZoneRG string = 'REPLACE-WITH-EXISTING-DNS-ZONE-RG'
param dnsSubscriptionId string = 'REPLACE-WITH-EXISTING-DNS-ZONE-SUBSCRIPTION-ID'
```
> NOTE: All above values should not be empty or the script will not behave as expected.

## Subnet requirements

### APIM subnet
Dedicated subnet to be used by APIM with /27 or higher address space.

This subnet must have special NSG for APIM to integrate with smoothly. Specific rules are available in the [APIM documentation](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet?tabs=stv2#configure-nsg-rules).

```bicep
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = {
    name: apimNsgName
    location: location
    tags: union(tags, { 'azd-service-name': apimNsgName })
    properties: {
        securityRules: [
        {
            name: 'AllowPublicAccess' // Only External
            properties: {
                protocol: 'Tcp'
                sourcePortRange: '*'
                destinationPortRange: '443'
                sourceAddressPrefix: 'Internet'
                destinationAddressPrefix: 'VirtualNetwork'
                access: 'Allow'
                priority: 3000
                direction: 'Inbound'
            }
        }
        {
            name: 'AllowAPIMManagement'
            properties: {
                protocol: 'Tcp'
                sourcePortRange: '*'
                destinationPortRange: '3443'
                sourceAddressPrefix: 'ApiManagement'
                destinationAddressPrefix: 'VirtualNetwork'
                access: 'Allow'
                priority: 3010
                direction: 'Inbound'
            }
        }
        {
            name: 'AllowAPIMLoadBalancer'
            properties: {
                protocol: '*'
                sourcePortRange: '*'
                destinationPortRange: '6390'
                sourceAddressPrefix: 'AzureLoadBalancer'
                destinationAddressPrefix: 'VirtualNetwork'
                access: 'Allow'
                priority: 3020
                direction: 'Inbound'
            }
        }
        {
            name: 'AllowAzureTrafficManager' //Only External
            properties: {
                protocol: 'Tcp'
                sourcePortRange: '*'
                destinationPortRange: '443'
                sourceAddressPrefix: 'AzureTrafficManager'
                destinationAddressPrefix: 'VirtualNetwork'
                access: 'Allow'
                priority: 3030
                direction: 'Inbound'
            }
        }
        {
            name: 'AllowStorage'
            properties: {
                protocol: 'Tcp'
                sourcePortRange: '*'
                destinationPortRange: '443'
                sourceAddressPrefix: 'Storage'
                destinationAddressPrefix: 'VirtualNetwork'
                access: 'Allow'
                priority: 3000
                direction: 'Outbound'
            }
        }
        {
            name: 'AllowSql'
            properties: {
                protocol: 'Tcp'
                sourcePortRange: '*'
                destinationPortRange: '1433'
                sourceAddressPrefix: 'Sql'
                destinationAddressPrefix: 'VirtualNetwork'
                access: 'Allow'
                priority: 3010
                direction: 'Outbound'
            }
        }
        {
            name: 'AllowKeyVault'
            properties: {
                protocol: 'Tcp'
                sourcePortRange: '*'
                destinationPortRange: '443'
                sourceAddressPrefix: 'AzureKeyVault'
                destinationAddressPrefix: 'VirtualNetwork'
                access: 'Allow'
                priority: 3020
                direction: 'Outbound'
            }
        }
        {
            name: 'AllowMonitor'
            properties: {
                protocol: 'Tcp'
                sourcePortRange: '*'
                destinationPortRanges: ['1886', '443']
                sourceAddressPrefix: 'AzureMonitor'
                destinationAddressPrefix: 'VirtualNetwork'
                access: 'Allow'
                priority: 3030
                direction: 'Outbound'
            }
        }
        ]
    }
}
```

Also important point if this subnet has a route table, it should include a route to handle APIM management control plane traffic.

```bicep
resource apimRouteTable 'Microsoft.Network/routeTables@2023-11-01' = {
  name: apimRouteTableName
  location: location
  tags: union(tags, { 'azd-service-name': apimRouteTableName })
  properties: {
    routes: [
      {
        name: 'apim-management'
        properties: {
          addressPrefix: 'ApiManagement'
          nextHopType: 'Internet'
        }
      }
      // Add additional routes as required
    ]
  }
}
```

>**Note:** If you are using APIM with V2 SKU (StandardV2 or PremiumV2), Route Table requirement is not needed (it only applies to APIM classic version Developer and Premium).

If there is a forced tunneling applied on the subnet (directly through route table or in-directly through BGP), you need to enable service endpoints for the following services (only on the APIM subnet):

- Azure Active Directory
- Event Hubs
- Key Vault
- Service Bus
- SQL Database
- Storage

>**Note:** If you are using APIM with V2 SKU (StandardV2 or PremiumV2), this subnet will be delegated to ```Microsoft.Web/serverFarms```. This will allow APIM to access private AI endpoints for OpenAI and Cognitive Services.

### Function app subnet

This is a delegated to ```Microsoft.Web/serverFarms``` subnet with /27 or higher that will be used by Azure Function App responsible for ingesting AI usage data published by APIM to Event Hub and push them to Cosmos DB.

Azure Function is using private endpoints and managed identity to connect to both Event Hub and Cosmos DB.

Example of the subnet definition:

```bicep
...
{
    name: functionAppSubnetName
    properties: {
        addressPrefix: functionAppSubnetAddressPrefix
        networkSecurityGroup: functionAppNsg.id == '' ? null : {
        id: functionAppNsg.id
        }
        privateEndpointNetworkPolicies: 'Enabled'
        privateLinkServiceNetworkPolicies: 'Enabled'
        delegations: [
        {
            name: 'Microsoft.Web/serverFarms'
            properties: {
            serviceName: 'Microsoft.Web/serverFarms'
            }
        }
        ]
    }
}
...

```

### Private endpoints subnet
This subnet is used by private endpoints to connect to the services. It should have a /27 or higher address space.

Example of the subnet definition:

```bicep
{
    name: privateEndpointSubnetName
    properties: {
        addressPrefix: privateEndpointSubnetAddressPrefix
        networkSecurityGroup: privateEndpointNsg.id == '' ? null : {
        id: privateEndpointNsg.id
        }
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Enabled'
    }
}
```

>**Note:** APIM V2 SKU (StandardV2 or PremiumV2) requires private endpoints to be configured in the private endpoint subnet to ensure private inbound connectivity.

### Private DNS Zones
The following private zones are expected to be available in one resource group (it can be different resource group from the virtual network) and already linked to the virtual network:

```bicep
var openAiPrivateDnsZoneName = 'privatelink.openai.azure.com'
var keyVaultPrivateDnsZoneName = 'privatelink.vaultcore.azure.net'
var monitorPrivateDnsZoneName = 'privatelink.monitor.azure.com'
var eventHubPrivateDnsZoneName = 'privatelink.servicebus.windows.net'
var cosmosDbPrivateDnsZoneName = 'privatelink.documents.azure.com'
var storageBlobPrivateDnsZoneName = 'privatelink.blob.core.windows.net'
var storageFilePrivateDnsZoneName = 'privatelink.file.core.windows.net'
var storageTablePrivateDnsZoneName = 'privatelink.table.core.windows.net'
var storageQueuePrivateDnsZoneName = 'privatelink.queue.core.windows.net'
var aiCogntiveServicesDnsZoneName = 'privatelink.cognitiveservices.azure.com'
var apimV2SkuDnsZoneName = 'privatelink.azure-api.net' // This is only needed if you are using APIM with V2 SKU (StandardV2 or PremiumV2)
```

Depending on the setup you have for managing private dns zones, you have these options:

- If the provisioner has ```Network Contributor``` role on the existing private zones, you can use the existing zones by updating the following information in the (main.bicep)[../infra/main.bicep] as outline in the next section
- If the provisioner does not have the required permissions, leave both ```dnsZoneRG``` and ```dnsSubscriptionId``` empty and the script will create the required private zones so it can associate it with the private endpoint configurations. 
    - In this case, you can update the central dns zones directly with the endpoints records or just configure the private endpoint directly to use the central zones.

For Azure Monitor resources, this needs to be configured after the deployment as it has a special private link service that needs to be centralized across all networks and subscriptions.


### API Management Internal Mode

Accelerator provision APIM by default as ```External``` gateway, which means that it is still fully provisioned in the network, but it has a public endpoint.

This to allow the accelerator to be accessible as soon as the deployment completes.

This can be changed in the [main.bicep](../infra/main.bicep). 

The following parameter can be updated to internal if needed:

```bicep
description('Network type for API Management service. Leave blank to use default naming conventions.')
@allowed([ 'None', 'External', 'Internal' ])
param apimNetworkType string = 'External'
```

If you are using the internal mode, you need to make sure that the DNS resolution is configured as mentioned in the prerequisites of this guide.

