# Enterprise Provisioning with DevOps
This guide outlines the enterprise provisioning strategy for the Contoso AI Hub Gateway using Azure Developer CLI (azd) and GitHub Actions for CI/CD. It focuses on managing multiple environments (development, test, production) through a branch-based approach in a single repository.

CI/CD pipelines automatically deploy from environment branches when changes are merged.

## 🔄 CI/CD Pipeline Implementation

### GitHub Actions Workflow

#### Development Environment Pipeline
Create `.github/workflows/deploy-dev.yml`:

```yaml
name: Deploy to Development

on:
  push:
    branches: [ environments/dev ]
  pull_request:
    branches: [ environments/dev ]

env:
  AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  AZURE_ENV_NAME: contoso-ai-hub-dev
  AZURE_LOCATION: eastus

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: development
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Install azd
      uses: Azure/setup-azd@v1.0.0
      
    - name: Log in with Azure (Federated Credentials)
      run: |
        azd auth login \
          --client-id "${{ env.AZURE_CLIENT_ID }}" \
          --federated-credential-provider "github" \
          --tenant-id "${{ env.AZURE_TENANT_ID }}"
          
    - name: Provision Infrastructure
      run: |
        azd env new ${{ env.AZURE_ENV_NAME }} --location ${{ env.AZURE_LOCATION }}
        azd provision --no-prompt
        
    - name: Deploy Application
      run: azd deploy --no-prompt
```

#### Production Environment Pipeline
Create `.github/workflows/deploy-prod.yml`:

```yaml
name: Deploy to Production

on:
  push:
    branches: [ environments/prod ]
  workflow_dispatch:
    inputs:
      confirm_deployment:
        description: 'Type "deploy" to confirm production deployment'
        required: true
        default: ''

env:
  AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID_PROD }}
  AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID_PROD }}
  AZURE_ENV_NAME: contoso-ai-hub-prod
  AZURE_LOCATION: eastus

jobs:
  validate:
    runs-on: ubuntu-latest
    if: github.event_name == 'workflow_dispatch' && github.event.inputs.confirm_deployment == 'deploy'
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Install azd
      uses: Azure/setup-azd@v1.0.0
      
    - name: Validate Bicep Templates
      run: |
        az bicep build --file infra/main.bicep
        
  deploy:
    runs-on: ubuntu-latest
    needs: validate
    environment: 
      name: production
      url: ${{ steps.deploy.outputs.gateway_url }}
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Install azd
      uses: Azure/setup-azd@v1.0.0
      
    - name: Log in with Azure (Federated Credentials)
      run: |
        azd auth login \
          --client-id "${{ env.AZURE_CLIENT_ID }}" \
          --federated-credential-provider "github" \
          --tenant-id "${{ env.AZURE_TENANT_ID }}"
          
    - name: Provision Infrastructure
      run: |
        azd env new ${{ env.AZURE_ENV_NAME }} --location ${{ env.AZURE_LOCATION }}
        azd provision --no-prompt
        
    - name: Deploy Application
      id: deploy
      run: |
        azd deploy --no-prompt
        echo "gateway_url=$(azd env get-values | grep APIM_GATEWAY_URL | cut -d'=' -f2)" >> $GITHUB_OUTPUT
        
    - name: Run Smoke Tests
      run: |
        # Add smoke test scripts here
        echo "Running smoke tests..."
```

### Azure DevOps Pipeline

Create `azure-pipelines-prod.yml`:

```yaml
trigger:
  branches:
    include:
    - environments/prod

pool:
  vmImage: 'ubuntu-latest'

variables:
  azureServiceConnection: 'contoso-prod-service-connection'
  environmentName: 'contoso-ai-hub-prod'
  azureLocation: 'eastus'

stages:
- stage: Validate
  displayName: 'Validate Infrastructure'
  jobs:
  - job: ValidateBicep
    displayName: 'Validate Bicep Templates'
    steps:
    - task: AzureCLI@2
      displayName: 'Validate Bicep'
      inputs:
        azureSubscription: $(azureServiceConnection)
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az bicep build --file infra/main.bicep
          
- stage: Deploy
  displayName: 'Deploy to Production'
  dependsOn: Validate
  condition: succeeded()
  jobs:
  - deployment: DeployInfrastructure
    displayName: 'Deploy Infrastructure'
    environment: 'production'
    strategy:
      runOnce:
        deploy:
          steps:
          - checkout: self
          
          - task: AzureCLI@2
            displayName: 'Install Azure Developer CLI'
            inputs:
              azureSubscription: $(azureServiceConnection)
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                curl -fsSL https://aka.ms/install-azd.sh | bash
                
          - task: AzureCLI@2
            displayName: 'Deploy with AZD'
            inputs:
              azureSubscription: $(azureServiceConnection)
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                azd env new $(environmentName) --location $(azureLocation)
                azd provision --no-prompt
                azd deploy --no-prompt
```

### Secret Management

#### GitHub Secrets Configuration
```bash
# Required secrets for GitHub Actions
AZURE_CLIENT_ID          # Service Principal Client ID
AZURE_TENANT_ID           # Azure AD Tenant ID
AZURE_SUBSCRIPTION_ID     # Target Subscription ID

# Production-specific secrets
AZURE_CLIENT_ID_PROD      # Production Service Principal
AZURE_SUBSCRIPTION_ID_PROD # Production Subscription
```

#### Azure Service Principal Setup
```bash
# Create service principal for CI/CD
az ad sp create-for-rbac \
  --name "contoso-ai-hub-cicd" \
  --role "Contributor" \
  --scopes "/subscriptions/{subscription-id}" \
  --sdk-auth

# Configure federated credentials for GitHub
az ad app federated-credential create \
  --id {app-id} \
  --parameters '{
    "name": "contoso-ai-hub-github",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:contoso/ai-hub-gateway-enterprise:environment:production",
    "description": "GitHub Actions deployment",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### Pipeline Triggers and Approvals

#### Environment-based Deployment Flow
1. **Development**: Auto-deploy on push to `environments/dev`
2. **Test**: Auto-deploy on push to `environments/test`
3. **Production**: Manual approval required, deploy on push to `environments/prod`

#### Approval Gates Configuration
```yaml
# GitHub Environment Protection Rules
environments:
  production:
    protection_rules:
      - type: required_reviewers
        required_reviewers:
          - users: ["cloud-architect", "security-lead"]
          - teams: ["platform-team"]
      - type: wait_timer
        wait_timer: 5 # minutes
      - type: branch_policy
        branch_policy:
          protected_branches: true
```

## 🏗️ Deployment Scenarios

The enterprise repository strategy supports multiple deployment scenarios using branch-based environment management.

### Scenario 1: Development Environment
```bash
# Clone enterprise repository and switch to dev branch
git clone https://github.com/contoso/ai-hub-gateway-enterprise.git
cd ai-hub-gateway-enterprise
git checkout environments/dev

# Deploy using customized dev parameters
azd env new contoso-ai-hub-dev
azd env set AZURE_LOCATION eastus
azd up
```

### Scenario 2: Production Deployment via CI/CD
```bash
# Push changes to production branch triggers automated deployment
git checkout environments/prod
git pull origin main  # Merge latest changes
# Edit main.bicep with production-specific parameters
git add infra/main.bicep
git commit -m "Update production capacity to 200 TPM"
git push origin environments/prod  # Triggers GitHub Actions workflow
```

### Scenario 3: Manual Production Deployment
```bash
# Deploy production manually with branch-specific parameters
git checkout environments/prod
azd auth login
azd env new contoso-ai-hub-prod
azd env set AZURE_LOCATION eastus
azd env set AZURE_SUBSCRIPTION_ID "prod-subscription-id"
azd up
```

### Scenario 4: BYOVNET Enterprise Deployment
```bash
# Use existing networking infrastructure
git checkout environments/prod

# Parameters already configured in main.bicep:
# - useExistingVnet: true
# - existingVnetRG: "rg-contoso-networking" 
# - vnetName: "vnet-contoso-hub"

azd env new contoso-enterprise-prod
azd env set AZURE_LOCATION eastus
azd up
```

### Scenario 5: Multi-Region Disaster Recovery
```bash
# Deploy to secondary region for DR
git checkout environments/dr
# main.bicep configured with:
# - location: "westus2" 
# - deploymentCapacity: 50 (reduced capacity for DR)

azd env new contoso-ai-hub-dr
azd env set AZURE_LOCATION westus2
azd up
```

## 📋 Best Practices

### Repository Management
- Use environment branches for different deployment targets
- Implement branch protection rules for production environments
- Keep main branch synchronized with upstream accelerator updates
- Tag releases for environment deployments

### Parameter Management
- Embed environment-specific parameters directly in `main.bicep` per branch
- Use environment variables only for sensitive values (subscription IDs, tenant IDs)
- Document parameter customizations in branch-specific README files
- Version control all parameter changes with descriptive commit messages

### Naming Conventions
- Use consistent naming patterns across environments: `{org}-{solution}-{env}`
- Include organization, environment, and region identifiers
- Avoid special characters that may cause deployment issues
- Maintain naming consistency across all Azure resources

### Security
- Always use private endpoints in production environments
- Enable Entra ID authentication for API access in production
- Implement proper RBAC on resource groups and subscriptions
- Use Azure Key Vault for sensitive configuration values
- Configure service principal with minimal required permissions

### Capacity Planning
- Start with conservative capacity and scale up based on usage patterns
- Monitor usage patterns and adjust TPM/RPM limits accordingly
- Consider regional distribution for high availability and performance
- Plan for disaster recovery scenarios with secondary regions
- Implement proper throttling policies for different user tiers

### Cost Optimization
- Use appropriate SKUs for each environment (Developer for dev, Premium for prod)
- Monitor usage through Power BI dashboards and set up cost alerts
- Consider reserved instances for predictable workloads
- Implement proper tagging for cost allocation and chargeback

### CI/CD Best Practices
- Use federated credentials instead of client secrets for GitHub Actions
- Implement approval gates for production deployments
- Run validation and smoke tests after deployment
- Store environment-specific secrets in GitHub environments or Azure Key Vault
- Implement proper rollback procedures for failed deployments
- Implement resource tagging for cost allocation
- Monitor usage through the Power BI dashboard
- Consider reserved instances for predictable workloads

### Monitoring
- Enable Application Insights dashboards
- Set up alerts for throttling events
- Monitor API Management metrics
- Track cost and usage trends

### Network Security
- Use NSGs to restrict traffic flow
- Implement Azure Firewall for egress control
- Consider ExpressRoute for hybrid connectivity
- Plan DNS resolution for private endpoints

### Change Management
- Version control all parameter files
- Use separate environments for dev/test/prod
- Implement proper CI/CD pipelines
- Document customizations and deviations

### CI/CD Environment Variables

For automated deployments, set these in your CI/CD system:

```bash
# Authentication (GitHub Actions / Azure DevOps)
AZURE_CLIENT_ID="your-service-principal-client-id"
AZURE_TENANT_ID="your-tenant-id"  
AZURE_SUBSCRIPTION_ID="your-subscription-id"

# Environment-specific overrides
ENVIRONMENT_NAME="contoso-ai-hub-prod"
LOCATION="eastus"
APIM_SKU="Premium"
DEPLOYMENT_CAPACITY="100"
```