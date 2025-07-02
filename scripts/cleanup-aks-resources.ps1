# Script to help clean up existing AKS resources that might be conflicting
# Run this script before attempting to redeploy the backend systems

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId
)

# Set subscription if provided
if ($SubscriptionId) {
    Write-Host "Setting subscription to: $SubscriptionId" -ForegroundColor Yellow
    az account set --subscription $SubscriptionId
}

Write-Host "Checking for existing AKS clusters in resource group: $ResourceGroupName" -ForegroundColor Cyan

# Check for existing AKS clusters
$aksClusters = az aks list --resource-group $ResourceGroupName --query "[].{Name:name, State:powerState.code, NodeResourceGroup:nodeResourceGroup}" --output table

if ($aksClusters) {
    Write-Host "Found existing AKS clusters:" -ForegroundColor Yellow
    Write-Host $aksClusters
    
    $confirmation = Read-Host "Do you want to delete these AKS clusters? (y/N)"
    if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
        $clusterNames = az aks list --resource-group $ResourceGroupName --query "[].name" --output tsv
        foreach ($clusterName in $clusterNames) {
            Write-Host "Deleting AKS cluster: $clusterName" -ForegroundColor Red
            az aks delete --resource-group $ResourceGroupName --name $clusterName --yes --no-wait
        }
        Write-Host "AKS cluster deletion initiated. This may take several minutes..." -ForegroundColor Yellow
    }
} else {
    Write-Host "No existing AKS clusters found in the resource group." -ForegroundColor Green
}

# Check for subnet usage
Write-Host "`nChecking subnet usage in VNet..." -ForegroundColor Cyan
$vnets = az network vnet list --resource-group $ResourceGroupName --query "[].name" --output tsv

foreach ($vnetName in $vnets) {
    Write-Host "Checking VNet: $vnetName" -ForegroundColor White
    $subnets = az network vnet subnet list --resource-group $ResourceGroupName --vnet-name $vnetName --query "[].{Name:name, AddressPrefix:addressPrefix, ProvisioningState:provisioningState}" --output table
    Write-Host $subnets
}

Write-Host "`nScript completed. Wait for AKS deletion to complete before redeploying." -ForegroundColor Green
Write-Host "You can check deletion status with: az aks list --resource-group $ResourceGroupName" -ForegroundColor Cyan
