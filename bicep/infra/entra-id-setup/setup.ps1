<#
.SYNOPSIS
    Creates an Entra ID App Registration and configures APIM JWT named values
    for the AI Hub Gateway. No redeployment of the landing zone required.

.DESCRIPTION
    This script is a self-contained Entra ID onboarding tool that:
    1. Creates (or reuses) an Entra ID App Registration with OAuth2 scopes and app roles
    2. Creates a service principal
    3. Generates a client secret and stores it in Key Vault
    4. Configures APIM named values for JWT authentication directly
    5. Stores values as azd environment variables for future deployments

    It is idempotent: re-running finds existing resources and updates configuration.
    
    After running this script, APIM is immediately configured for JWT authentication.
    No 'azd up' redeployment is needed.

.PARAMETER EnvironmentName
    Name of the azd environment (used in app registration display name).
    Defaults to AZURE_ENV_NAME from azd environment.

.PARAMETER KeyVaultName
    Name of the Key Vault to store the client secret.
    Defaults to KEY_VAULT_NAME from azd environment.

.PARAMETER ApimResourceGroup
    Resource group containing the APIM instance.
    Defaults to AZURE_RESOURCE_GROUP from azd environment, or auto-discovered.

.PARAMETER ApimName
    Name of the APIM instance to configure.
    Defaults to APIM_NAME from azd environment, or auto-discovered.

.EXAMPLE
    # Using azd environment values (recommended after first azd up):
    pwsh ./setup.ps1

    # Explicit parameters:
    pwsh ./setup.ps1 -EnvironmentName "citadel-dev" -KeyVaultName "kv-abc123" -ApimResourceGroup "rg-citadel-dev" -ApimName "apim-abc123"

.NOTES
    App-role definitions do not create client app-role assignments.
    Assign roles directly to application and managed-identity service principals.
    Security-group assignments supply user roles, not roles for service-principal members.
    The three roles and access_as_user scope use four permission definitions.
    Entra ID defaults to 700 definitions shared by roles and exposed delegated scopes;
    these also count toward the separate 1,200-entry application manifest limit.

    Prerequisites:
    - Azure CLI authenticated (az login) with Application.ReadWrite.All permission
    - Key Vault must exist and deployer must have Key Vault Secrets Officer role
    - APIM instance must exist (deployed via azd up)
    - azd environment configured (if not passing explicit parameters)
#>

param(
    [string]$EnvironmentName = "",
    [string]$KeyVaultName = "",
    [string]$ApimResourceGroup = "",
    [string]$ApimName = ""
)

$ErrorActionPreference = "Stop"

function Invoke-AzdCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $command = Get-Command azd -ErrorAction Stop
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            # Windows PowerShell treats native stderr as errors even when the command succeeds.
            $ErrorActionPreference = "Continue"
            $PSNativeCommandUseErrorActionPreference = $false
            $output = & $command @Arguments 2>$stderrFile
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        $diagnostic = Get-Content -LiteralPath $stderrFile -Raw
        if (-not [string]::IsNullOrWhiteSpace($diagnostic)) {
            Write-Warning $diagnostic.Trim()
        }
        if ($exitCode -ne 0) {
            # Do not include argument values: env set can contain the client secret.
            $message = "azd $($Arguments[0]) $($Arguments[1]) failed (exit code $exitCode)."
            if ($AllowFailure) {
                Write-Warning $message
                return
            }
            throw $message
        }
        $output
    } finally {
        Remove-Item -LiteralPath $stderrFile -Force
    }
}

# ── Resolve parameters from azd environment if not provided ──
if ([string]::IsNullOrWhiteSpace($EnvironmentName)) {
    $EnvironmentName = Invoke-AzdCommand -Arguments @("env", "get-value", "AZURE_ENV_NAME")
    if ([string]::IsNullOrWhiteSpace($EnvironmentName)) {
        Write-Error "EnvironmentName not provided and AZURE_ENV_NAME not found in azd environment."
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
    $KeyVaultName = Invoke-AzdCommand -Arguments @("env", "get-value", "KEY_VAULT_NAME")
    if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
        Write-Error "KeyVaultName not provided and KEY_VAULT_NAME not found in azd environment. Run 'azd up' first to create the Key Vault, then re-run this script."
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($ApimResourceGroup)) {
    $ApimResourceGroup = Invoke-AzdCommand -Arguments @("env", "get-value", "AZURE_RESOURCE_GROUP") -AllowFailure
    if ([string]::IsNullOrWhiteSpace($ApimResourceGroup)) {
        # Auto-discover from the APIM resource if APIM_NAME is known
        $knownApimName = Invoke-AzdCommand -Arguments @("env", "get-value", "APIM_NAME") -AllowFailure
        if (-not [string]::IsNullOrWhiteSpace($knownApimName)) {
            Write-Host "  Discovering resource group from APIM '$knownApimName'..." -ForegroundColor Gray
            $apimResource = az resource list --name $knownApimName --resource-type "Microsoft.ApiManagement/service" --query "[0].resourceGroup" --output tsv 2>$null
            if (-not [string]::IsNullOrWhiteSpace($apimResource)) {
                $ApimResourceGroup = $apimResource
                Write-Host "  Discovered RG: $ApimResourceGroup" -ForegroundColor Gray
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($ApimResourceGroup)) {
        Write-Error "ApimResourceGroup not provided and could not be auto-discovered. Provide -ApimResourceGroup or ensure AZURE_RESOURCE_GROUP is set (run 'azd up' with latest template)."
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($ApimName)) {
    $ApimName = Invoke-AzdCommand -Arguments @("env", "get-value", "APIM_NAME") -AllowFailure
    if ([string]::IsNullOrWhiteSpace($ApimName)) {
        # Auto-discover APIM in the resource group
        Write-Host "  Discovering APIM instance in resource group '$ApimResourceGroup'..." -ForegroundColor Gray
        $apimList = az apim list --resource-group $ApimResourceGroup --query "[0].name" --output tsv 2>$null
        if (-not [string]::IsNullOrWhiteSpace($apimList)) {
            $ApimName = $apimList
            Write-Host "  Discovered APIM: $ApimName" -ForegroundColor Gray
        } else {
            Write-Error "ApimName not provided and could not auto-discover APIM in resource group '$ApimResourceGroup'. Provide -ApimName or run 'azd up' first."
            exit 1
        }
    }
}

$AppDisplayName = "ai-citadel-gateway-${EnvironmentName}"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Entra ID App Registration Setup" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Environment:  $EnvironmentName" -ForegroundColor Gray
Write-Host "  App Name:     $AppDisplayName" -ForegroundColor Gray
Write-Host "  Key Vault:    $KeyVaultName" -ForegroundColor Gray
Write-Host "  APIM RG:      $ApimResourceGroup" -ForegroundColor Gray
Write-Host "  APIM Name:    $ApimName" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ── Verify Azure CLI auth ──
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Error "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
}
$tenantId = $account.tenantId
Write-Host "  Tenant:       $tenantId" -ForegroundColor Gray
Write-Host "  User:         $($account.user.name)" -ForegroundColor Gray
Write-Host ""

# ── 1. Create or get existing App Registration ──
Write-Host "[1/6] Checking for existing app registration..." -ForegroundColor Yellow
$existingApp = az ad app list --display-name $AppDisplayName --output json 2>$null | ConvertFrom-Json

# Define the canonical set of app roles for the gateway
$gatewayAppRoles = @(
    @{
        allowedMemberTypes = @("User", "Application")
        description        = "Invoke LLM model endpoints (chat completions, embeddings)"
        displayName        = "Model.Invoke"
        isEnabled          = $true
        id                 = "00000000-0000-0000-0000-000000000003"
        value              = "Model.Invoke"
    }
    @{
        allowedMemberTypes = @("User", "Application")
        description        = "Invoke MCP tool endpoints"
        displayName        = "MCP.Invoke"
        isEnabled          = $true
        id                 = "00000000-0000-0000-0000-000000000004"
        value              = "MCP.Invoke"
    }
    @{
        allowedMemberTypes = @("User", "Application")
        description        = "Invoke agent endpoints"
        displayName        = "Agent.Invoke"
        isEnabled          = $true
        id                 = "00000000-0000-0000-0000-000000000005"
        value              = "Agent.Invoke"
    }
)

if ($existingApp -and $existingApp.Count -gt 0) {
    $app = $existingApp[0]
    $appId = $app.appId
    $appObjectId = $app.id
    Write-Host "  Found existing: $appId" -ForegroundColor Green

    # ── 1a. Ensure app roles are up-to-date on existing registration ──
    Write-Host "  Checking app roles..." -ForegroundColor Yellow
    $updatedRoles = @($app.appRoles | Where-Object { $null -ne $_ })
    $rolesChanged = $false
    foreach ($gatewayRole in $gatewayAppRoles) {
        $currentRole = $updatedRoles | Where-Object { $_.id -eq $gatewayRole.id }
        if (-not $currentRole) {
            $updatedRoles += $gatewayRole
            $rolesChanged = $true
            continue
        }
        # Keep role IDs and assignment settings while updating canonical role metadata.
        foreach ($property in @("displayName", "value", "description")) {
            if ($currentRole.$property -cne $gatewayRole[$property]) {
                $currentRole.$property = $gatewayRole[$property]
                $rolesChanged = $true
            }
        }
    }
    if ($rolesChanged) {
        Write-Host "  Updating app roles..." -ForegroundColor Yellow
        $patchPayload = @{ appRoles = $updatedRoles }
        $patchTempFile = [System.IO.Path]::GetTempFileName()
        try {
            $patchPayload | ConvertTo-Json -Depth 10 | Set-Content -Path $patchTempFile -Encoding UTF8
            az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" --headers "Content-Type=application/json" --body "@$patchTempFile" --output none
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to update app roles. Check Microsoft Graph permissions and retry setup."
            } else {
                Write-Host "  App roles updated successfully" -ForegroundColor Green
            }
        } finally {
            Remove-Item -Path $patchTempFile -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "  App roles are up-to-date" -ForegroundColor Green
    }
} else {
    Write-Host "  Creating new app registration..." -ForegroundColor Yellow

    # Write JSON body to temp file to avoid shell escaping issues with az rest --body
    $appPayload = @{
        displayName = $AppDisplayName
        signInAudience = "AzureADMyOrg"
        isFallbackPublicClient = $true
        api = @{
            requestedAccessTokenVersion = 2
            oauth2PermissionScopes = @(
                @{
                    adminConsentDescription  = "Allow access to AI Hub Gateway API"
                    adminConsentDisplayName  = "Access AI Hub Gateway API"
                    isEnabled                = $true
                    id                       = "00000000-0000-0000-0000-000000000001"
                    type                     = "User"
                    userConsentDescription   = "Allow access to AI Hub Gateway API"
                    userConsentDisplayName   = "Access AI Hub Gateway API"
                    value                    = "access_as_user"
                }
            )
        }
        appRoles = $gatewayAppRoles
        requiredResourceAccess = @(
            @{
                resourceAppId  = "00000003-0000-0000-c000-000000000000"
                resourceAccess = @(
                    @{
                        id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
                        type = "Scope"
                    }
                )
            }
        )
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        $appPayload | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding UTF8

        $appResult = az rest --method POST --uri "https://graph.microsoft.com/v1.0/applications" --headers "Content-Type=application/json" --body "@$tempFile" --output json | ConvertFrom-Json

        if (-not $appResult -or -not $appResult.appId) {
            Write-Error "Failed to create app registration."
            exit 1
        }

        $appId = $appResult.appId
        $appObjectId = $appResult.id
        Write-Host "  Created: $appId" -ForegroundColor Green
    } finally {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
}

if ([string]::IsNullOrWhiteSpace($appId)) {
    Write-Error "App registration ID is empty. Cannot continue."
    exit 1
}

# ── 1b. Set Application ID URI ──
Write-Host "[1b/6] Configuring Application ID URI..." -ForegroundColor Yellow
$identifierUri = "api://$appId"

# Check current identifierUris
$currentApp = az rest --method GET --uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" --query "identifierUris" --output json 2>$null | ConvertFrom-Json
if (-not $currentApp -or $currentApp.Count -eq 0 -or $currentApp -notcontains $identifierUri) {
    $uriPayload = @{ identifierUris = @($identifierUri) }
    $uriTempFile = [System.IO.Path]::GetTempFileName()
    try {
        $uriPayload | ConvertTo-Json -Depth 5 | Set-Content -Path $uriTempFile -Encoding UTF8
        az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" --headers "Content-Type=application/json" --body "@$uriTempFile" --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to set Application ID URI: $identifierUri"
            exit 1
        }
        Write-Host "  Set Application ID URI: $identifierUri" -ForegroundColor Green
    } finally {
        Remove-Item -Path $uriTempFile -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "  Application ID URI already configured: $identifierUri" -ForegroundColor Green
}

# ── 2. Ensure Service Principal exists ──
Write-Host "[2/6] Ensuring service principal exists..." -ForegroundColor Yellow
$spCheck = az ad sp list --filter "appId eq '$appId'" --output json 2>$null | ConvertFrom-Json
if (-not $spCheck -or $spCheck.Count -eq 0) {
    az ad sp create --id $appId --output none 2>$null
    Write-Host "  Created service principal" -ForegroundColor Green
} else {
    Write-Host "  Service principal exists" -ForegroundColor Green
}

# ── 3. Generate client secret ──
Write-Host "[3/6] Generating client secret..." -ForegroundColor Yellow
$secretResult = az ad app credential reset --id $appObjectId --display-name "Generated by Entra ID Setup" --years 2 --output json | ConvertFrom-Json
$clientSecret = $secretResult.password

if ([string]::IsNullOrWhiteSpace($clientSecret)) {
    Write-Error "Failed to create client secret."
    exit 1
}
Write-Host "  Client secret generated" -ForegroundColor Green

# ── 4. Store in Key Vault ──
Write-Host "[4/6] Storing client secret in Key Vault..." -ForegroundColor Yellow
$kvResult = az keyvault secret set --vault-name $KeyVaultName --name "ENTRA-APP-CLIENT-SECRET" --value $clientSecret --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "" -ForegroundColor Red
    Write-Host "  Failed to store secret in Key Vault '$KeyVaultName'." -ForegroundColor Red
    Write-Host "  Error: $kvResult" -ForegroundColor Red
    Write-Host "" -ForegroundColor Yellow
    Write-Host "  Possible causes:" -ForegroundColor Yellow
    Write-Host "    - You don't have 'Key Vault Secrets Officer' role on the Key Vault" -ForegroundColor Yellow
    Write-Host "    - The Key Vault has a firewall blocking access from your IP" -ForegroundColor Yellow
    Write-Host "    - The Key Vault name '$KeyVaultName' is incorrect" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    Write-Host "  To grant yourself access, run:" -ForegroundColor Cyan
    Write-Host "    az role assignment create --role `"Key Vault Secrets Officer`" --assignee `"$($account.user.name)`" --scope (az keyvault show --name $KeyVaultName --query id --output tsv)" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Yellow
    Write-Host "  Continuing without Key Vault storage. The secret is still stored in azd environment." -ForegroundColor Yellow
} else {
    Write-Host "  Stored as ENTRA-APP-CLIENT-SECRET" -ForegroundColor Green
}

# ── 5. Configure APIM JWT Named Values ──
Write-Host "[5/6] Configuring APIM JWT named values..." -ForegroundColor Yellow

$loginEndpoint = "https://login.microsoftonline.com"
$jwtIssuer = "$loginEndpoint/$tenantId/v2.0"
$jwtOpenIdConfigUrl = "$loginEndpoint/$tenantId/v2.0/.well-known/openid-configuration"

# Named values to create/update in APIM
$namedValues = @(
    @{ Name = "JWT-TenantId";          DisplayName = "JWT-TenantId";          Value = $tenantId;          Secret = $false }
    @{ Name = "JWT-AppRegistrationId"; DisplayName = "JWT-AppRegistrationId"; Value = $appId;             Secret = $false }
    @{ Name = "JWT-Issuer";            DisplayName = "JWT-Issuer";            Value = $jwtIssuer;         Secret = $false }
    @{ Name = "JWT-OpenIdConfigUrl";   DisplayName = "JWT-OpenIdConfigUrl";   Value = $jwtOpenIdConfigUrl; Secret = $false }
)

foreach ($nv in $namedValues) {
    $nvName = $nv.Name
    
    # Check if named value already exists
    $existing = az apim nv show --resource-group $ApimResourceGroup --service-name $ApimName --named-value-id $nvName --output json 2>$null | ConvertFrom-Json
    
    if ($existing) {
        # Update existing named value
        az apim nv update --resource-group $ApimResourceGroup --service-name $ApimName --named-value-id $nvName --value $nv.Value --output none 2>$null
        Write-Host "  Updated: $nvName" -ForegroundColor Green
    } else {
        # Create new named value
        az apim nv create --resource-group $ApimResourceGroup --service-name $ApimName --named-value-id $nvName --display-name $nv.DisplayName --value $nv.Value --output none 2>$null
        Write-Host "  Created: $nvName" -ForegroundColor Green
    }
}

Write-Host "  APIM JWT named values configured" -ForegroundColor Green

# ── 6. Store values in azd environment ──
Write-Host "[6/6] Storing values in azd environment..." -ForegroundColor Yellow
Invoke-AzdCommand -Arguments @("env", "set", "AZURE_CLIENT_ID", $appId)
Invoke-AzdCommand -Arguments @("env", "set", "AZURE_TENANT_ID", $tenantId)
Invoke-AzdCommand -Arguments @("env", "set", "AZURE_AUDIENCE", "api://$appId")
Invoke-AzdCommand -Arguments @("env", "set", "ENTRA_CLIENT_SECRET", $clientSecret)
Write-Host "  Values stored in azd environment" -ForegroundColor Green

# ── Summary ──
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Entra ID Setup Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  App Display Name:     $AppDisplayName" -ForegroundColor Gray
Write-Host "  Client ID:            $appId" -ForegroundColor Gray
Write-Host "  Tenant ID:            $tenantId" -ForegroundColor Gray
Write-Host "  App ID URI:           api://$appId" -ForegroundColor Gray
Write-Host "  Audience:             api://$appId" -ForegroundColor Gray
Write-Host "  KV Secret:            ENTRA-APP-CLIENT-SECRET" -ForegroundColor Gray
Write-Host "  APIM Named Values:    JWT-TenantId, JWT-AppRegistrationId," -ForegroundColor Gray
Write-Host "                        JWT-Issuer, JWT-OpenIdConfigUrl" -ForegroundColor Gray
Write-Host ""
Write-Host "  APIM is now configured for JWT authentication." -ForegroundColor Cyan
Write-Host "  No redeployment needed. Configure access contracts" -ForegroundColor Cyan
Write-Host "  with jwtAuth.enabled=true to enforce JWT per product." -ForegroundColor Cyan
Write-Host "  For role authorization, assign the required Invoke roles directly" -ForegroundColor Cyan
Write-Host "  to each application or managed-identity service principal." -ForegroundColor Cyan
Write-Host "  Security-group role assignments apply to users, not service-principal members." -ForegroundColor Cyan
Write-Host "  See guides/jwt-client-identity-permissions.md for assignment instructions." -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
