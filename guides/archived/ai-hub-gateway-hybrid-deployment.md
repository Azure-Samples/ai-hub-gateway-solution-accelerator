# Hybrid deployment of AI Hub Gateway

Azure API Management (APIM) has 3 components: 
- API Gateway: is the runtime component that handles API requests and can be deployed on Azure as Managed Gateway or anywhere else (like on-premises) as Self-hosted Gateway.
- Developer Portal: is the self-service portal for developers to discover and consume APIs
- API Management Service: is the management plane that manages the API Gateway and Developer Portal.

Building on the APIM API Gateway capability of being hosted anywhere, I will deploy it in this walkthrough on Azure Container App (which in a similar fashion can be deployed on-premises on a compliant Kubernetes cluster or VM). 

The Developer Portal and API Management Service will remain hosted on Azure.

## Creating containerized hosting environment

I will be creating here a resource group, container app environment and a container app to host APIM API gateway.

```bash
PROJECT=ai-gateway
RESOURCE_GROUP=rg-$PROJECT
ACA_SELFHOSTED_NAME=aca-$PROJECT-app
ACA_SELFHOSTED_ENV=aca-$PROJECT-env
LOCATION=northeurope

az group create --name $RESOURCE_GROUP --location $LOCATION

az containerapp env create --name $ACA_SELFHOSTED_ENV --resource-group $RESOURCE_GROUP --location $LOCATION

# Getting APIM self-hosted gateway endpoint and token
# You can get these values from APIM - Gateway - Self-hosted gateway configuration - Deployment - Docker
ENDPOINT="<APIM configuration endpoint>"
TOKEN="REPLACE_WITH_YOUR_KEY"


az containerapp create --name $ACA_SELFHOSTED_NAME \
  --environment $ACA_SELFHOSTED_ENV \
  --resource-group $RESOURCE_GROUP \
  --ingress 'external' \
  --image mcr.microsoft.com/azure-api-management/gateway:2.5.0 \
  --target-port 8080 \
  --query properties.configuration.ingress.fqdn \
  --env-vars "config.service.endpoint"="$ENDPOINT" "config.service.auth"="$TOKEN" "net.server.http.forwarded.proto.enabled"="true"

# Testing the deployment (you should get empty 200 response)
GATEWAY_URL=$(az containerapp show --name $ACA_SELFHOSTED_NAME --resource-group $RESOURCE_GROUP --query "properties.configuration.ingress.fqdn" --output tsv)
echo $GATEWAY_URL
curl -i https://$GATEWAY_URL/status-0123456789abcdef

```

