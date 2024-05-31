using System;
using System.Text;
using Azure.Messaging.EventHubs;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Azure.Identity;
using Microsoft.Azure.Cosmos;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Microsoft.Extensions.Configuration;

namespace AIHubGateway.UsageProcessing
{
    public class UsageProcessorFunction
    {
        private readonly ILogger<UsageProcessorFunction> _logger;
        private CosmosClient _cosmosClient;
        private Container _container;

        public UsageProcessorFunction(ILogger<UsageProcessorFunction> logger, IConfiguration configuration)
        {
            _logger = logger;
            //_logger.LogInformation("UsageProcessorFunction created v1");

            // Read Cosmos DB settings from IConfiguration
            string accountEndpoint = configuration["CosmosAccountEndpoint"] ?? string.Empty;
            string databaseName = configuration["CosmosDatabaseName"] ?? string.Empty;
            string containerName = configuration["CosmosContainerName"] ?? string.Empty;
            string cosmosDbManagedIdentityClientId = configuration["CosmosManagedIdentityId"] ?? string.Empty; // using the same identity used with event hub
            
            //_logger.LogInformation($"Cosmos DB settings: acc:{accountEndpoint}, db:{databaseName}, cont:{containerName}, mi:{cosmosDbManagedIdentityClientId}");
            
            // Create a new CosmosClient using the DefaultAzureCredential
            var credential = string.IsNullOrEmpty(cosmosDbManagedIdentityClientId) ? new DefaultAzureCredential() : new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = cosmosDbManagedIdentityClientId });
            _cosmosClient = new CosmosClient(accountEndpoint, credential);
            _container = _cosmosClient.GetContainer(databaseName, containerName);
        }

        [Function(nameof(UsageProcessorFunction))]
        public async Task Run([EventHubTrigger("ai-usage", Connection = "EventHubConnection")] EventData[] events)
        {
            try
            {
            foreach (EventData @event in events)
            {
                //_logger.LogInformation("Event Body: {body}", Encoding.UTF8.GetString(@event.Body.ToArray()));

                // Convert the event body to a dynamic object
                dynamic data = JsonConvert.DeserializeObject(Encoding.UTF8.GetString(@event.Body.ToArray()));

                // Insert the event into Cosmos DB
                ItemResponse<JObject> response = await _container.CreateItemAsync(data);
            }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error processing event: ${ex.Message}");
            }
        }
    }
}
