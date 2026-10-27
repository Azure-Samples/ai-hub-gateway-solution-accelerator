<#
.SYNOPSIS
    Creates an Entra ID App Registration for JWT authentication with the Unified AI API.
    Equivalent to the Terraform azuread_application resource in APIM-Unified-AI-Gateway-Sample.

.DESCRIPTION
    This script runs as an azd pre-provision hook. It creates (or reuses) an Entra ID
    app registration with OAuth2 scopes, app roles, service principal, and client secret.
    Values are stored as azd environment variables consumed by the Bicep deployment.

    Mirrors the UAIG Terraform Entra-Id module:
    - App Registration with sign_in_audience = AzureADMyOrg
    - OAuth2 permission scope (access_as_user)
    - Identifier URI (api://{clientId})
    - Service Principal
    - Client Secret (stored in Key Vault via Bicep, value passed as env var)

.NOTES
    Requires: az login with permissions to create app registrations (Application.ReadWrite.All)
    Client authorization requires direct app-role assignments to application and
    managed-identity service principals. Security-group role assignments apply to
    users; service-principal group membership does not supply app roles in tokens.
    This script does not create client app-role assignments.
#>

param(
    [string]$EnvironmentName = $env:AZURE_ENV_NAME
)

$ErrorActionPreference = "Stop"

# Check if Entra auth is enabled
$entraAuth = azd env get-value AZURE_ENTRA_AUTH 2>$null
if ($entraAuth -ne "true") {
    Write-Host "Entra authentication is not enabled (AZURE_ENTRA_AUTH != true). Skipping app registration." -ForegroundColor Yellow
    exit 0
}

# Check if client ID is already configured (user-provided existing app registration)
$existingClientId = azd env get-value AZURE_CLIENT_ID 2>$null
if (-not [string]::IsNullOrWhiteSpace($existingClientId) -and $existingClientId -ne "not-configured") {
    Write-Host "Entra app registration already configured (AZURE_CLIENT_ID = $existingClientId). Skipping creation." -ForegroundColor Yellow
    exit 0
}

Write-Host "Setting up Entra ID App Registration for JWT authentication..." -ForegroundColor Cyan

# Get current context
$account = az account show --output json | ConvertFrom-Json
$tenantId = $account.tenantId
$currentUserId = $account.user.name

Write-Host "Tenant ID: $tenantId" -ForegroundColor Gray
Write-Host "Current user: $currentUserId" -ForegroundColor Gray

$appDisplayName = "ai-hub-gateway-$EnvironmentName-unified-ai"

# Check if app already exists
Write-Host "Checking for existing app registration '$appDisplayName'..." -ForegroundColor Gray
$existingApp = az ad app list --display-name $appDisplayName --output json 2>$null | ConvertFrom-Json

if ($existingApp -and $existingApp.Count -gt 0) {
    $app = $existingApp[0]
    $appId = $app.appId
    $appObjectId = $app.id
    Write-Host "Found existing app registration: $appId" -ForegroundColor Green
} else {
    # Create the App Registration (mirrors azuread_application in Terraform)
    Write-Host "Creating new app registration..." -ForegroundColor Gray

    $appJson = @{
        displayName = $appDisplayName
        signInAudience = "AzureADMyOrg"
        api = @{
            requestedAccessTokenVersion = 2
        }
        requiredResourceAccess = @(
            @{
                resourceAppId = "00000003-0000-0000-c000-000000000000"  # Microsoft Graph
                resourceAccess = @(
                    @{
                        id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"  # User.Read
                        type = "Scope"
                    }
                )
            }
        )
    } | ConvertTo-Json -Depth 10

    $appResult = az rest --method POST --uri "https://graph.microsoft.com/v1.0/applications" --headers "Content-Type=application/json" --body $appJson --output json | ConvertFrom-Json
    $appId = $appResult.appId
    $appObjectId = $appResult.id
    Write-Host "Created app registration: $appId (ObjectId: $appObjectId)" -ForegroundColor Green

    # Set identifier URI
    Write-Host "Setting identifier URI..." -ForegroundColor Gray
    $identifierUriJson = @{
        identifierUris = @("api://$appId")
    } | ConvertTo-Json -Depth 5

    az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" --headers "Content-Type=application/json" --body $identifierUriJson --output none
    Write-Host "Identifier URI set to api://$appId" -ForegroundColor Green
}

# Ensure service principal exists (mirrors azuread_service_principal in Terraform)
Write-Host "Ensuring service principal exists..." -ForegroundColor Gray
$spCheck = az ad sp list --filter "appId eq '$appId'" --output json 2>$null | ConvertFrom-Json
if (-not $spCheck -or $spCheck.Count -eq 0) {
    az ad sp create --id $appId --output none 2>$null
    Write-Host "Service principal created." -ForegroundColor Green
} else {
    Write-Host "Service principal already exists." -ForegroundColor Green
}

# Create a client secret (mirrors azuread_application_password in Terraform)
Write-Host "Creating client secret..." -ForegroundColor Gray
$secretResult = az ad app credential reset --id $appObjectId --display-name "Generated by azd" --years 2 --output json | ConvertFrom-Json
$clientSecret = $secretResult.password

if ([string]::IsNullOrWhiteSpace($clientSecret)) {
    Write-Error "Failed to create client secret."
    exit 1
}
Write-Host "Client secret created successfully." -ForegroundColor Green

# Store values as azd environment variables
Write-Host "Storing values in azd environment..." -ForegroundColor Gray
azd env set AZURE_CLIENT_ID $appId
azd env set AZURE_TENANT_ID $tenantId
azd env set AZURE_AUDIENCE "api://$appId"
azd env set ENTRA_CLIENT_SECRET $clientSecret

Write-Host "" -ForegroundColor Cyan
Write-Host "Entra ID App Registration complete!" -ForegroundColor Green
Write-Host "  App Display Name: $appDisplayName" -ForegroundColor Gray
Write-Host "  Client ID: $appId" -ForegroundColor Gray
Write-Host "  Tenant ID: $tenantId" -ForegroundColor Gray
Write-Host "  Audience: api://$appId" -ForegroundColor Gray
Write-Host "  Client Secret: [stored in azd env as ENTRA_CLIENT_SECRET]" -ForegroundColor Gray
Write-Host ""
Write-Host "These values will be used by the Bicep deployment to configure APIM JWT named values." -ForegroundColor Cyan
Write-Host "For role authorization, assign gateway app roles directly to application and managed-identity service principals." -ForegroundColor Cyan
Write-Host "Security-group role assignments apply to users, not service-principal members. See guides/jwt-client-identity-permissions.md." -ForegroundColor Cyan
