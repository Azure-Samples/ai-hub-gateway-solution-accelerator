$ErrorActionPreference = "Stop"
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot "..\setup.ps1"), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors.Message -join "; ") }
foreach ($definition in $ast.EndBlock.Statements | Where-Object {
    $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $_.Name -in @("Get-SetupGraphValues", "Set-ValidationRoleAssignment", "Initialize-ValidationClient", "Initialize-JwtValidation")
}) {
    Invoke-Expression $definition.Extent.Text
}
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$script:requests = [System.Collections.Generic.List[object]]::new()
$script:assignments = @{}
$script:negative = $null
$script:negativeSp = $null
$script:positive = $null
$script:positiveSp = $null
$script:failPatch = $false
$script:gateway = [pscustomobject]@{
    api = [pscustomobject]@{
        oauth2PermissionScopes = @([pscustomobject]@{
            value = "access_as_user"; id = "scope-id"; isEnabled = $true
        })
        preAuthorizedApplications = @([pscustomobject]@{
            appId = "existing-client"; delegatedPermissionIds = @("existing-scope")
        })
    }
}
function Invoke-SetupGraph {
    param([string]$Method = "GET", [string]$Path, [hashtable]$Body)
    $script:requests.Add([pscustomobject]@{ Method = $Method; Path = $Path; Body = $Body })
    if ($Path -eq "me") { return [pscustomobject]@{ id = "user-id" } }
    if ($Path -eq "applications/gateway-object" -and $Method -eq "GET") { return $script:gateway }
    if ($Path -eq "applications/gateway-object" -and $Method -eq "PATCH") {
        if ($script:failPatch) { throw "fixture Graph permissions failure" }
        $script:gateway.api.preAuthorizedApplications = $Body.api.preAuthorizedApplications
        return
    }
    if ($Path -like "applications?*" -and $Method -eq "GET") {
        if ($Path.Contains("validation-client")) {
            return [pscustomobject]@{ value = @($script:positive | Where-Object { $null -ne $_ }) }
        }
        return [pscustomobject]@{ value = @($script:negative | Where-Object { $null -ne $_ }) }
    }
    if ($Path -eq "applications" -and $Method -eq "POST") {
        if ($Body.displayName.EndsWith("validation-client")) {
            $script:positive = [pscustomobject]@{ id = "positive-object"; appId = "positive-client" }
            return $script:positive
        }
        $script:negative = [pscustomobject]@{ id = "negative-object"; appId = "negative-client" }
        return $script:negative
    }
    if ($Path.StartsWith("servicePrincipals?") -and $Path.Contains("gateway-client")) {
        return [pscustomobject]@{ value = @([pscustomobject]@{ id = "gateway-sp" }) }
    }
    if ($Path.StartsWith("servicePrincipals?") -and $Path.Contains("negative-client")) {
        return [pscustomobject]@{ value = @($script:negativeSp | Where-Object { $null -ne $_ }) }
    }
    if ($Path.StartsWith("servicePrincipals?") -and $Path.Contains("positive-client")) {
        return [pscustomobject]@{ value = @($script:positiveSp | Where-Object { $null -ne $_ }) }
    }
    if ($Path -eq "servicePrincipals" -and $Method -eq "POST") {
        if ($Body.appId -eq "positive-client") {
            $script:positiveSp = [pscustomobject]@{ id = "positive-sp" }
            return $script:positiveSp
        }
        $script:negativeSp = [pscustomobject]@{ id = "negative-sp" }
        return $script:negativeSp
    }
    if ($Path.EndsWith("/appRoleAssignments")) {
        if (-not $script:assignments.ContainsKey($Path)) {
            $script:assignments[$Path] = [System.Collections.Generic.List[object]]::new()
        }
        if ($Method -eq "GET") { return [pscustomobject]@{ value = @($script:assignments[$Path].ToArray()) } }
        $script:assignments[$Path].Add([pscustomobject]$Body)
        return [pscustomobject]@{ id = "assignment" }
    }
    if ($Path -eq "applications/negative-object/addPassword" -and $Method -eq "POST") {
        return [pscustomobject]@{ secretText = "fixture-negative-secret" }
    }
    if ($Path -eq "applications/positive-object/addPassword" -and $Method -eq "POST") {
        return [pscustomobject]@{ secretText = "fixture-positive-secret" }
    }
    if ($Path -eq "paged") {
        return [pscustomobject]@{ value = @("first"); '@odata.nextLink' = "next-page" }
    }
    if ($Path -eq "next-page") { return [pscustomobject]@{ value = @("second") } }
    throw "Unexpected Graph fixture request: $Method $Path"
}

$result = Initialize-JwtValidation -ApplicationId "gateway-client" -ApplicationObjectId "gateway-object" -DisplayName "gateway"
Assert-True ($result.ClientId -eq "positive-client" -and $result.ClientSecret -eq "fixture-positive-secret") "Missing positive client outputs."
Assert-True ($result.NegativeClientId -eq "negative-client" -and $result.NegativeClientSecret -eq "fixture-negative-secret") "Missing negative client outputs."
Assert-True ($result.UserId -eq "user-id") "Incorrect signed-in user output."
$rolePosts = @($requests | Where-Object { $_.Method -eq "POST" -and $_.Path.EndsWith("/appRoleAssignments") })
Assert-True ($rolePosts.Count -eq 3) "Expected three direct role assignments."
$modelRole = "00000000-0000-0000-0000-000000000003"
$mcpRole = "00000000-0000-0000-0000-000000000004"
Assert-True ($assignments["servicePrincipals/positive-sp/appRoleAssignments"][0].appRoleId -eq $modelRole) "Application must have Model.Invoke."
Assert-True ($assignments["users/user-id/appRoleAssignments"][0].appRoleId -eq $modelRole) "Signed-in user must have Model.Invoke."
Assert-True ($assignments["servicePrincipals/negative-sp/appRoleAssignments"][0].appRoleId -eq $mcpRole) "Negative client must have only MCP.Invoke."
Assert-True (@($requests | Where-Object { $_.Path.StartsWith("groups/") }).Count -eq 0) "Service principals must not rely on groups."
$cli = $gateway.api.preAuthorizedApplications | Where-Object { $_.appId -eq "04b07795-8ddb-461a-bbee-02f9e1bf7b46" }
Assert-True ($cli.delegatedPermissionIds -contains "scope-id") "Azure CLI delegated scope was not preauthorized."
Assert-True ($gateway.api.preAuthorizedApplications.Count -eq 2) "Other preauthorized clients must be preserved."
Write-Host "PASS: Setup prepares direct application/user/negative assignments and Azure CLI delegated consent."

$null = Initialize-JwtValidation -ApplicationId "gateway-client" -ApplicationObjectId "gateway-object" -DisplayName "gateway"
$rolePosts = @($requests | Where-Object { $_.Method -eq "POST" -and $_.Path.EndsWith("/appRoleAssignments") })
Assert-True ($rolePosts.Count -eq 3) "Rerunning setup duplicated role assignments."
Assert-True ($gateway.api.preAuthorizedApplications.Count -eq 2) "Rerunning setup duplicated preauthorized clients."
Assert-True (@($requests | Where-Object { $_.Method -eq "POST" -and $_.Path -eq "applications" }).Count -eq 2) "Rerunning setup duplicated the validation applications."
Write-Host "PASS: Identity and permission setup is idempotent."

$pages = @(Get-SetupGraphValues -Path "paged")
Assert-True (($pages -join ",") -eq "first,second") "Graph pagination was not followed."
Write-Host "PASS: Role assignment lookup supports paginated Graph responses."

$assignments["servicePrincipals/negative-sp/appRoleAssignments"].Add([pscustomobject]@{
    resourceId = "gateway-sp"; appRoleId = $modelRole
})
$failed = $false
try {
    $null = Initialize-JwtValidation -ApplicationId "gateway-client" -ApplicationObjectId "gateway-object" -DisplayName "gateway"
} catch {
    if ($_.Exception.Message -notlike "*unexpectedly has Model.Invoke*") { throw }
    $failed = $true
}
Assert-True $failed "An incorrectly privileged negative client must stop setup."
$script:failPatch = $true
$failed = $false
try {
    $null = Initialize-JwtValidation -ApplicationId "gateway-client" -ApplicationObjectId "gateway-object" -DisplayName "gateway"
} catch {
    if ($_.Exception.Message -notlike "*Graph permissions failure*") { throw }
    $failed = $true
}
Assert-True $failed "Graph authorization failures must stop setup."
Write-Host "PASS: Invalid negative assignments and Graph permission failures are explicit."
