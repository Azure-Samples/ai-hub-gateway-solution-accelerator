using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Azure.Messaging.EventHubs;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace AI.Hub.Gateway.UsageIngestion
{
    public static class AIUsageIngestion
    {
    [FunctionName("AIUsageEventHub")]
        public static async Task Run([EventHubTrigger("ai-usage", Connection = "EventHubConnection")] EventData[] events,
                [CosmosDB(
                    databaseName: "ai-usage-db",
                    containerName: "ai-usage-container",
                    Connection = "CosmosDBConnection")] IAsyncCollector<JObject> usage,
         ILogger log)
        {
            var exceptions = new List<Exception>();

            foreach (EventData eventData in events)
            {
                try
                {
                    // Replace these two lines with your processing logic.
                    log.LogInformation($"C# Event Hub trigger function processed a message: {eventData.EventBody}");
                    var eventString = eventData.EventBody.ToString();
                    var eventObject = JObject.Parse(eventString);
                    usage.AddAsync(eventObject).Wait();
                    await Task.Yield();
                }
                catch (Exception e)
                {
                    // We need to keep processing the rest of the batch - capture this exception and continue.
                    // Also, consider capturing details of the message that failed processing so it can be processed again later.
                    exceptions.Add(e);
                }
            }

            // Once processing of the batch is complete, if any messages in the batch failed processing throw an exception so that there is a record of the failure.

            if (exceptions.Count > 1)
                throw new AggregateException(exceptions);

            if (exceptions.Count == 1)
                throw exceptions.Single();
        }
    }
}
