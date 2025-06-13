########
# Script to create an Event Hub logger in Azure API Management for OpenAI usage metrics manually (Bicep code is already doing this).
# This script assumes you have the Azure PowerShell module installed and are logged in to your Azure account, or you can run it in Azure Cloud Shell.
# Make sure to replace the placeholders with your actual values.
########

# Selecting target subscription
$subcriptionId = "<SubscriptionId>"
Set-AzContext -Subscription $subcriptionId

# API Management service-specific details
$apimServiceName = "apim-ai-gateway"
$resourceGroupName = "rg-ai-gateway"

# Event Hub connection string
$eventHubConnectionString = "Endpoint=sb://<EventHubsNamespace>.servicebus.windows.net/;SharedAccessKeyName=<KeyName>;SharedAccessKey=<key"

# Create logger
$context = New-AzApiManagementContext -ResourceGroupName $resourceGroupName -ServiceName $apimServiceName
New-AzApiManagementLogger -Context $context -LoggerId "usage-eventhub-logger" -Name "usage-eventhub-logger" -ConnectionString $eventHubConnectionString -Description "Event Hub logger for OpenAI usage metrics"

# If you have configured PII masking with data saving, you need to set its logger
$eventHubPIIConnectionString = "Endpoint=sb://<EventHubsNamespace>.servicebus.windows.net/;SharedAccessKeyName=<KeyName>;SharedAccessKey=<key>"
New-AzApiManagementLogger -Context $context -LoggerId "pii-usage-eventhub-logger" -Name "pii-usage-eventhub-logger" -ConnectionString $eventHubPIIConnectionString -Description "Event Hub logger for PII usage data"