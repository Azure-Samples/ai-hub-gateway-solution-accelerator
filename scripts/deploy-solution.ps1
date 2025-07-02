# Deployment script for AI Hub Gateway Solution
# Run this after cleaning up any conflicting AKS resources

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [string]$Location = "East US 2",
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId
)

# Set subscription if provided
if ($SubscriptionId) {
    Write-Host "Setting subscription to: $SubscriptionId" -ForegroundColor Yellow
    az account set --subscription $SubscriptionId
}

Write-Host "Starting deployment of AI Hub Gateway Solution to resource group: $ResourceGroupName" -ForegroundColor Cyan

# Change to the infra directory
$infraPath = Join-Path $PSScriptRoot ".." "infra"
if (Test-Path $infraPath) {
    Set-Location $infraPath
    Write-Host "Changed to infra directory: $infraPath" -ForegroundColor Green
} else {
    Write-Error "Infra directory not found at: $infraPath"
    exit 1
}

# Validate the main template first
Write-Host "Validating Bicep template..." -ForegroundColor Yellow
$validationResult = az deployment group validate --resource-group $ResourceGroupName --template-file "main.bicep" --parameters location="$Location" 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Template validation failed:"
    Write-Host $validationResult -ForegroundColor Red
    exit 1
} else {
    Write-Host "Template validation successful!" -ForegroundColor Green
}

# Deploy the template
Write-Host "Starting deployment..." -ForegroundColor Yellow
$deploymentName = "ai-hub-gateway-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file "main.bicep" `
    --parameters location="$Location" `
    --name $deploymentName `
    --verbose

if ($LASTEXITCODE -eq 0) {
    Write-Host "Deployment completed successfully!" -ForegroundColor Green
    Write-Host "Deployment name: $deploymentName" -ForegroundColor Cyan
    
    # Show the deployed resources
    Write-Host "`nDeployed resources:" -ForegroundColor Cyan
    az resource list --resource-group $ResourceGroupName --query "[].{Name:name, Type:type, Location:location}" --output table
} else {
    Write-Error "Deployment failed. Check the error messages above."
    Write-Host "You can check deployment status with:" -ForegroundColor Yellow
    Write-Host "az deployment group show --resource-group $ResourceGroupName --name $deploymentName" -ForegroundColor White
}
