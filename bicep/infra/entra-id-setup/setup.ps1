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
    Prepares JWT validation: direct Model.Invoke assignments for a validation client
    service principal and current Azure CLI user, an MCP.Invoke-only negative client,
    and Azure CLI preauthorization for access_as_user.
    Assign other client roles directly to application and managed-identity service principals.
    Security-group assignments supply user roles, not roles for service-principal members.
    The three roles and access_as_user scope use four permission definitions.
    Entra ID defaults to 700 definitions shared by roles and exposed delegated scopes;
    these also count toward the separate 1,200-entry application manifest limit.

    Prerequisites:
    - Azure CLI authenticated as a user (az login), with application write and
      app-role assignment permissions (e.g. Cloud Application Administrator)
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

function Invoke-SetupCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $command = Get-Command $CommandName -ErrorAction Stop
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
            $message = "$CommandName $($Arguments[0]) $($Arguments[1]) failed (exit code $exitCode)."
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

function Invoke-AzdCommand {
    param([string[]]$Arguments, [switch]$AllowFailure)
    Invoke-SetupCommand -CommandName azd -Arguments $Arguments -AllowFailure:$AllowFailure
}

function Invoke-SetupGraph {
    param([string]$Method = "GET", [string]$Path, [hashtable]$Body)
    $uri = if ($Path.StartsWith("https://graph.microsoft.com/v1.0/")) {
        $Path
    } else {
        "https://graph.microsoft.com/v1.0/$Path"
    }
    $arguments = @("rest", "--method", $Method, "--uri", $uri, "--output", "json")
    $bodyFile = $null
    try {
        if ($null -ne $Body) {
            $bodyFile = [System.IO.Path]::GetTempFileName()
            $Body | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $bodyFile -Encoding UTF8
            $arguments += @("--headers", "Content-Type=application/json", "--body", "@$bodyFile")
        }
        $result = Invoke-SetupCommand -CommandName az -Arguments $arguments
        if ($result) { $result | ConvertFrom-Json }
    } finally {
        if ($bodyFile) { Remove-Item -LiteralPath $bodyFile -Force }
    }
}

function Get-SetupGraphValues {
    param([string]$Path)
    do {
        $page = Invoke-SetupGraph -Path $Path
        if ($null -eq $page.value) { throw "Graph collection response did not contain value." }
        $page.value
        $Path = $page.'@odata.nextLink'
    } while ($Path)
}

function Set-ValidationRoleAssignment {
    param([string]$PrincipalId, [string]$ResourceId, [string]$RoleId, [string]$PrincipalType = "servicePrincipals")
    $path = "$PrincipalType/$PrincipalId/appRoleAssignments"
    $existing = @(Get-SetupGraphValues -Path $path) | Where-Object {
        $_.resourceId -eq $ResourceId -and $_.appRoleId -eq $RoleId
    }
    if (-not $existing) {
        $null = Invoke-SetupGraph -Method "POST" -Path $path -Body @{
            principalId = $PrincipalId; resourceId = $ResourceId; appRoleId = $RoleId
        }
    }
}

function Initialize-ValidationClient {
    param([string]$DisplayName, [string]$ResourceId, [string]$RoleId, [string]$ForbiddenRoleId = "")
    $filter = [Uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
    $applications = @(Get-SetupGraphValues -Path "applications?`$filter=$filter")
    if ($applications.Count -gt 1) { throw "Multiple validation app registrations matched $DisplayName." }
    $application = if ($applications.Count -eq 1) { $applications[0] } else {
        Invoke-SetupGraph -Method "POST" -Path "applications" -Body @{
            displayName = $DisplayName; signInAudience = "AzureADMyOrg"
        }
    }
    if (-not $application.id -or -not $application.appId) { throw "Validation application has no IDs." }
    $principals = @(Get-SetupGraphValues -Path "servicePrincipals?`$filter=appId eq '$($application.appId)'")
    if ($principals.Count -gt 1) { throw "Multiple validation service principals matched $DisplayName." }
    $principal = if ($principals.Count -eq 1) { $principals[0] } else {
        Invoke-SetupGraph -Method "POST" -Path "servicePrincipals" -Body @{ appId = $application.appId }
    }
    if (-not $principal.id) { throw "Validation service principal has no object ID." }
    if ($ForbiddenRoleId) {
        $assignments = @(Get-SetupGraphValues -Path "servicePrincipals/$($principal.id)/appRoleAssignments")
        if ($assignments | Where-Object { $_.resourceId -eq $ResourceId -and $_.appRoleId -eq $ForbiddenRoleId }) {
            throw "Negative-test client unexpectedly has Model.Invoke. Remove that assignment before rerunning setup."
        }
    }
    Set-ValidationRoleAssignment -PrincipalId $principal.id -ResourceId $ResourceId -RoleId $RoleId
    $credential = Invoke-SetupGraph -Method "POST" -Path "applications/$($application.id)/addPassword" -Body @{
        passwordCredential = @{
            displayName = "JWT validation client"
            endDateTime = [DateTime]::UtcNow.AddYears(1).ToString("o")
        }
    }
    if (-not $credential.secretText) { throw "Validation client credential was not returned." }
    [pscustomobject]@{ ClientId = $application.appId; ClientSecret = $credential.secretText }
}

function Initialize-JwtValidation {
    param([string]$ApplicationId, [string]$ApplicationObjectId, [string]$DisplayName)
    $profile = Invoke-SetupGraph -Path "me"
    if (-not $profile.id) { throw "JWT validation setup requires a signed-in Azure CLI user." }
    $gateway = Invoke-SetupGraph -Path "applications/$ApplicationObjectId"
    $scope = @($gateway.api.oauth2PermissionScopes | Where-Object {
        $_.value -eq "access_as_user" -and $_.isEnabled
    })
    if ($scope.Count -ne 1) { throw "Gateway must expose one enabled access_as_user delegated scope." }
    $cliAppId = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
    $preauthorized = @($gateway.api.preAuthorizedApplications | Where-Object { $null -ne $_ })
    $cli = $preauthorized | Where-Object { $_.appId -eq $cliAppId }
    if ($cli) {
        $cli.delegatedPermissionIds = @(@($cli.delegatedPermissionIds) + @($scope[0].id) | Select-Object -Unique)
    } else {
        $preauthorized += @{ appId = $cliAppId; delegatedPermissionIds = @($scope[0].id) }
    }
    $null = Invoke-SetupGraph -Method "PATCH" -Path "applications/$ApplicationObjectId" -Body @{
        api = @{
            requestedAccessTokenVersion = 2; preAuthorizedApplications = $preauthorized
            oauth2PermissionScopes = @($gateway.api.oauth2PermissionScopes)
        }
    }
    $principals = @(Get-SetupGraphValues -Path "servicePrincipals?`$filter=appId eq '$ApplicationId'")
    if ($principals.Count -ne 1) { throw "Expected exactly one gateway service principal." }
    $resourceId = $principals[0].id
    $modelRoleId = "00000000-0000-0000-0000-000000000003"
    $mcpRoleId = "00000000-0000-0000-0000-000000000004"
    Set-ValidationRoleAssignment -PrincipalId $profile.id -ResourceId $resourceId -RoleId $modelRoleId -PrincipalType "users"
    $positive = Initialize-ValidationClient -DisplayName "$DisplayName-validation-client" -ResourceId $resourceId -RoleId $modelRoleId
    $negative = Initialize-ValidationClient -DisplayName "$DisplayName-validation-negative" -ResourceId $resourceId -RoleId $mcpRoleId -ForbiddenRoleId $modelRoleId
    [pscustomobject]@{
        ClientId = $positive.ClientId; ClientSecret = $positive.ClientSecret
        NegativeClientId = $negative.ClientId; NegativeClientSecret = $negative.ClientSecret
        UserId = $profile.id
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
if ($account.user.type -ne "user") {
    throw "Run setup with Azure CLI signed in as a user (az login); user-token validation cannot use an SP login."
}
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

Write-Host "  Preparing application, signed-in user and missing-model-role validation identities..." -ForegroundColor Yellow
$validationIdentity = Initialize-JwtValidation -ApplicationId $appId -ApplicationObjectId $appObjectId -DisplayName $AppDisplayName

# ── 3. Use the dedicated validation client credential ──
Write-Host "[3/6] Preparing client credential..." -ForegroundColor Yellow
$clientSecret = $validationIdentity.ClientSecret

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
Invoke-AzdCommand -Arguments @("env", "set", "ENTRA_CLIENT_ID", $validationIdentity.ClientId)
Invoke-AzdCommand -Arguments @("env", "set", "ENTRA_TENANT_ID", $tenantId)
Invoke-AzdCommand -Arguments @("env", "set", "ENTRA_AUDIENCE", "api://$appId")
Invoke-AzdCommand -Arguments @("env", "set", "ENTRA_VALIDATION_NEGATIVE_CLIENT_ID", $validationIdentity.NegativeClientId)
Invoke-AzdCommand -Arguments @("env", "set", "ENTRA_VALIDATION_NEGATIVE_CLIENT_SECRET", $validationIdentity.NegativeClientSecret)
Invoke-AzdCommand -Arguments @("env", "set", "ENTRA_VALIDATION_USER_ID", $validationIdentity.UserId)
Invoke-AzdCommand -Arguments @("env", "set", "AZURE_RESOURCE_GROUP", $ApimResourceGroup)
Invoke-AzdCommand -Arguments @("env", "set", "APIM_NAME", $ApimName)
Write-Host "  Values stored in azd environment" -ForegroundColor Green

# ── Summary ──
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Entra ID Setup Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  App Display Name:     $AppDisplayName" -ForegroundColor Gray
Write-Host "  Client ID:            $appId" -ForegroundColor Gray
Write-Host "  Validation Client:    $($validationIdentity.ClientId)" -ForegroundColor Gray
Write-Host "  Negative Client:      $($validationIdentity.NegativeClientId)" -ForegroundColor Gray
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
Write-Host "  JWT validation is ready: Model.Invoke for the validation app and signed-in user;" -ForegroundColor Cyan
Write-Host "  an MCP.Invoke-only client supplies the missing-Model.Invoke test token." -ForegroundColor Cyan
Write-Host "  Run validation/citadel-jwt-authentication-tests.ipynb using this azd environment." -ForegroundColor Cyan
Write-Host "  See guides/jwt-client-identity-permissions.md for assignment instructions." -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
