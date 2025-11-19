


## 📦 Source Control Strategy

### Repository Structure

```
ai-hub-gateway-solution-accelerator/
├── bicep/
│   └── infra/
│       ├── main.bicep                         # Main template
│       ├── main.bicepparam                    # Environment variables
│       ├── main.parameters.dev.bicepparam     # Dev config
│       ├── main.parameters.staging.bicepparam # Staging config
│       ├── main.parameters.prod.bicepparam    # Prod config
│       ├── abbreviations.json
│       └── modules/                           # Reusable modules
├── .azure/                                    # azd configuration
│   └── <env-name>/
│       ├── .env                               # Environment secrets
│       └── config.json
├── .github/
│   └── workflows/
│       ├── deploy-dev.yml
│       ├── deploy-staging.yml
│       └── deploy-prod.yml
└── azure-pipelines/
    ├── deploy-dev.yml
    ├── deploy-staging.yml
    └── deploy-prod.yml
```

### Version Control Best Practices

#### ✅ **DO** Commit

```bash
git add bicep/infra/main.bicep
git add bicep/infra/main.parameters.*.bicepparam
git add bicep/infra/modules/
git add .github/workflows/
git add azure-pipelines/
```

#### ❌ **DO NOT** Commit

```bash
# Never commit secrets!
.azure/*/.env                  # Contains secrets
*.secrets.bicepparam           # Any secrets file
*.local.bicepparam             # Local overrides
```

#### .gitignore Configuration

```gitignore
# Azure Developer CLI
.azure/*/.env
.azure/*/config.json

# Secrets and local overrides
*.secrets.bicepparam
*.local.bicepparam
*.secret.*

# Bicep build artifacts
*.bicep.json
*.bicepparam.json

# VS Code
.vscode/settings.json
```

### Branch Strategy

**GitFlow for Infrastructure:**

```
main (production)
├── develop (staging)
│   ├── feature/add-new-model
│   ├── feature/update-network
│   └── hotfix/fix-apim-policy
└── release/v1.2.0
```

**Deployment Flow:**
1. Develop in `feature/*` branches
2. Merge to `develop` → triggers staging deployment
3. Create `release/*` → triggers UAT deployment
4. Merge to `main` → triggers production deployment

---

## ⚙️ Deployment Automation Methods

Below approaches that can be used to automate the deployments using CI/CD pipelines.

### Azure DevOps Pipelines

**Best for:** Enterprise, CI/CD, automated deployments

#### Pipeline Configuration

**File:** `azure-pipelines/deploy-prod.yml`

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - bicep/infra/**

pool:
  vmImage: 'ubuntu-latest'

variables:
  - group: citadel-prod-secrets  # Variable group with secrets
  - name: azureSubscription
    value: 'Citadel-Production-ServiceConnection'
  - name: location
    value: 'eastus'
  - name: deploymentName
    value: 'citadel-prod-$(Build.BuildId)'

stages:
  - stage: Validate
    displayName: 'Validate Bicep Templates'
    jobs:
      - job: ValidateBicep
        steps:
          - task: AzureCLI@2
            displayName: 'Validate Bicep'
            inputs:
              azureSubscription: $(azureSubscription)
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                az deployment sub validate \
                  --location $(location) \
                  --template-file ./bicep/infra/main.bicep \
                  --parameters ./bicep/infra/main.parameters.prod.bicepparam

  - stage: Deploy
    displayName: 'Deploy to Production'
    dependsOn: Validate
    condition: succeeded()
    jobs:
      - deployment: DeployInfrastructure
        displayName: 'Deploy Citadel Infrastructure'
        environment: 'Production'
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                
                - task: AzureCLI@2
                  displayName: 'Deploy Bicep'
                  inputs:
                    azureSubscription: $(azureSubscription)
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    inlineScript: |
                      az deployment sub create \
                        --name $(deploymentName) \
                        --location $(location) \
                        --template-file ./bicep/infra/main.bicep \
                        --parameters ./bicep/infra/main.parameters.prod.bicepparam \
                        --parameters entraTenantId=$(ENTRA_TENANT_ID) \
                        --parameters entraClientId=$(ENTRA_CLIENT_ID)
                
                - task: AzureCLI@2
                  displayName: 'Get Deployment Outputs'
                  inputs:
                    azureSubscription: $(azureSubscription)
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    inlineScript: |
                      APIM_NAME=$(az deployment sub show \
                        --name $(deploymentName) \
                        --query properties.outputs.APIM_NAME.value -o tsv)
                      
                      APIM_URL=$(az deployment sub show \
                        --name $(deploymentName) \
                        --query properties.outputs.APIM_GATEWAY_URL.value -o tsv)
                      
                      echo "APIM Name: $APIM_NAME"
                      echo "Gateway URL: $APIM_URL"
                      
                      echo "##vso[task.setvariable variable=APIM_NAME;isOutput=true]$APIM_NAME"
                      echo "##vso[task.setvariable variable=APIM_URL;isOutput=true]$APIM_URL"

  - stage: PostDeploy
    displayName: 'Post-Deployment Validation'
    dependsOn: Deploy
    jobs:
      - job: ValidateDeployment
        steps:
          - task: AzureCLI@2
            displayName: 'Test APIM Gateway'
            inputs:
              azureSubscription: $(azureSubscription)
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                # Add validation tests here
                echo "Deployment validated successfully"
```

**Variable Group Setup:**

```bash
# Create variable group in Azure DevOps
ENTRA_TENANT_ID=<tenant-id>
ENTRA_CLIENT_ID=<client-id>
ENTRA_AUDIENCE=<audience>
```

---

### GitHub Actions

**Best for:** GitHub repositories, automated deployments

**File:** `.github/workflows/deploy-prod.yml`

```yaml
name: Deploy Production

on:
  push:
    branches:
      - main
    paths:
      - 'bicep/infra/**'
  workflow_dispatch:

env:
  AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  LOCATION: eastus

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Validate Bicep
        uses: azure/CLI@v1
        with:
          inlineScript: |
            az deployment sub validate \
              --location ${{ env.LOCATION }} \
              --template-file ./bicep/infra/main.bicep \
              --parameters ./bicep/infra/main.parameters.prod.bicepparam

  deploy:
    runs-on: ubuntu-latest
    needs: validate
    environment: production
    steps:
      - uses: actions/checkout@v4
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Deploy Infrastructure
        uses: azure/CLI@v1
        with:
          inlineScript: |
            DEPLOYMENT_NAME="citadel-prod-${{ github.run_number }}"
            
            az deployment sub create \
              --name $DEPLOYMENT_NAME \
              --location ${{ env.LOCATION }} \
              --template-file ./bicep/infra/main.bicep \
              --parameters ./bicep/infra/main.parameters.prod.bicepparam \
              --parameters entraTenantId=${{ secrets.ENTRA_TENANT_ID }} \
              --parameters entraClientId=${{ secrets.ENTRA_CLIENT_ID }}
            
            # Get outputs
            APIM_NAME=$(az deployment sub show \
              --name $DEPLOYMENT_NAME \
              --query properties.outputs.APIM_NAME.value -o tsv)
            
            echo "APIM_NAME=$APIM_NAME" >> $GITHUB_ENV
      
      - name: Post-Deployment Tests
        run: |
          echo "Deployed APIM: ${{ env.APIM_NAME }}"
          # Add validation tests
```

**GitHub Secrets Setup:**

```bash
AZURE_CREDENTIALS='{"clientId":"<client-id>","clientSecret":"<secret>","subscriptionId":"<sub-id>","tenantId":"<tenant-id>"}'
AZURE_SUBSCRIPTION_ID=<subscription-id>
ENTRA_TENANT_ID=<tenant-id>
ENTRA_CLIENT_ID=<client-id>
```

---