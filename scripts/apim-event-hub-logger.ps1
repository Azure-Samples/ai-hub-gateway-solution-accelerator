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