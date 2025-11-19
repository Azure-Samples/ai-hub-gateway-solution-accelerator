# AI Studio Integration

Azure AI Studio is a a unified platform for developing and deploying generative AI apps responsibly.

It offers prebuilt and customizable models, using your data to innovate at scale.

Integrating AI Hub Gateway with Azure AI Studio allows you to access the AI Hub Gateway governed AI services (like Azure OpenAI and Azure AI Search) to build AI solutions.

This guid provide details about how this integration can be done.

## Prerequisites

As AI Studio still requires to connect to AI Services using public endpoints, AI Hub Gateway APIM endpoint needs to be publicly accessible.

Azure OpenAI & AI Search endpoints can be integrated through APIM 
1.	Requires APIM to be public 

    a.	Directly using APIM native capability (networking is set to None or External) to have public endpoint (not recommended)
   
    b.	Or indirectly through customer network appliances where APIM is fully private with networking set to Internal (recommended)
2.	Keep in mind that AI Studio tries to query OpenAI service itself through ARM calls to retrieve list of deployment, you will get warnings like (model deployment can’t be read) as APIM is not exposing ARM APIs
3.	Selecting AI Hub Gateway connected resource in AI Studio (like prompt flow) connections and it will work as expected
4.	Above can scale basically to many other resources that AI Studio is capable of connecting to.

## Connected resources

Using AI-Hub-Gateway with AI Studio is possible today through ```Connected resources```.

