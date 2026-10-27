$ErrorActionPreference = "Stop"

$setupPath = Join-Path $PSScriptRoot "..\setup.ps1"
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $setupPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Setup script has syntax errors: $($parseErrors.Message -join '; ')"
}

# Execute only role definitions and registration branches; all Azure calls are mocked.
$rolesStatement = $ast.EndBlock.Statements | Where-Object {
    $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $_.Left.Extent.Text -eq '$gatewayAppRoles'
}
$registrationStatement = $ast.EndBlock.Statements | Where-Object {
    $_ -is [System.Management.Automation.Language.IfStatementAst] -and
    $_.Clauses[0].Item1.Extent.Text -eq '$existingApp -and $existingApp.Count -gt 0'
}
if (-not $rolesStatement -or -not $registrationStatement) {
    throw "Could not locate setup role definitions and registration branches."
}
Invoke-Expression $rolesStatement.Extent.Text
$registrationSource = $registrationStatement.Extent.Text

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$script:requests = [System.Collections.Generic.List[object]]::new()
$script:failUpdate = $false
function az {
    $arguments = @($args)
    Assert-True ($arguments[0] -eq "rest") "Unexpected Azure CLI call."
    $method = $arguments[[Array]::IndexOf($arguments, "--method") + 1]
    $bodyFile = $arguments[[Array]::IndexOf($arguments, "--body") + 1].Substring(1)
    $body = Get-Content -LiteralPath $bodyFile -Raw | ConvertFrom-Json
    $script:requests.Add([pscustomobject]@{
        Method = $method
        Body = $body
        BodyFile = $bodyFile
    })
    $global:LASTEXITCODE = 0
    if ($method -eq "POST") {
        return '{"appId":"fixture-client","id":"fixture-app"}'
    }
    Assert-True ($method -eq "PATCH") "Unexpected Graph method."
    if ($script:failUpdate) {
        $global:LASTEXITCODE = 1
    }
}

function Copy-Roles {
    $gatewayAppRoles | ConvertTo-Json -Depth 10 | ConvertFrom-Json
}

$expectedValues = "Model.Invoke,MCP.Invoke,Agent.Invoke"
$expectedIds = (3..5 | ForEach-Object { "00000000-0000-0000-0000-{0:d12}" -f $_ }) -join ","
Assert-True (($gatewayAppRoles.value -join ",") -ceq $expectedValues) "Incorrect canonical role values."
Assert-True (($gatewayAppRoles.id -join ",") -eq $expectedIds) "Canonical role IDs changed."
foreach ($role in $gatewayAppRoles) {
    Assert-True (($role.allowedMemberTypes | Sort-Object) -join "," -ceq "Application,User") "Roles must support direct application assignments and user assignments."
}

$AppDisplayName = "fixture-gateway"
$existingApp = @()
Invoke-Expression $registrationSource
Assert-True ($requests.Count -eq 1 -and $requests[0].Method -eq "POST") "New app must be created once."
Assert-True (($requests[0].Body.appRoles.value -join ",") -ceq $expectedValues) "New app roles differ."
Assert-True (($requests[0].Body.appRoles.id -join ",") -eq $expectedIds) "New app role IDs differ."
Assert-True (($requests[0].Body.appRoles.Count + $requests[0].Body.api.oauth2PermissionScopes.Count) -eq 4) "Expected three app roles and one delegated scope."
Write-Host "PASS: New registrations use the canonical invoke roles and stable IDs."

$requests.Clear()
$legacyRoles = Copy-Roles
foreach ($role in $legacyRoles) {
    $role.value = $role.value.Replace("Model.", "Models.").Replace(".Invoke", ".Read")
    $role.displayName = $role.value
    $role.description = $role.description.Replace("Invoke", "Access to")
}
$legacyRoles[1].isEnabled = $false
$legacyRoles[1].allowedMemberTypes = @("Application")
$customRole = [pscustomobject]@{
    id = "11111111-1111-1111-1111-111111111111"
    value = "Custom.Use"
    displayName = "Custom role"
    description = "Custom role description"
    isEnabled = $true
    allowedMemberTypes = @("User")
}
$existingApp = @([pscustomobject]@{
    appId = "fixture-client"; id = "fixture-app"; appRoles = $legacyRoles + @($customRole)
})
Invoke-Expression $registrationSource
Assert-True ($requests.Count -eq 1 -and $requests[0].Method -eq "PATCH") "Legacy roles must be updated."
$updated = @($requests[0].Body.appRoles)
Assert-True (($updated[0..2].value -join ",") -ceq $expectedValues) "Legacy role values were not renamed."
Assert-True (($updated[0..2].id -join ",") -eq $expectedIds) "Existing role IDs changed."
Assert-True (($updated[0..2].displayName -join ",") -ceq $expectedValues) "Role display names were not renamed."
Assert-True (-not $updated[1].isEnabled) "Existing enabled state must be retained."
Assert-True (($updated[1].allowedMemberTypes -join ",") -eq "Application") "Existing member types must be retained."
Assert-True (($updated.Count -eq 4) -and $updated[3].value -eq "Custom.Use") "Custom roles must be retained."
Assert-True (-not (Test-Path -LiteralPath $requests[0].BodyFile)) "PATCH temporary file was not removed."
Write-Host "PASS: Legacy roles update in place without changing IDs, settings or custom roles."

$requests.Clear()
Invoke-Expression $registrationSource
Assert-True ($requests.Count -eq 0) "Repeated setup must not patch unchanged roles."
Write-Host "PASS: Existing canonical roles require no update."

foreach ($initialRoles in @(@($gatewayAppRoles[0], $customRole), @())) {
    $requests.Clear()
    $existingApp = @([pscustomobject]@{
        appId = "fixture-client"; id = "fixture-app"; appRoles = $initialRoles
    })
    Invoke-Expression $registrationSource
    Assert-True ($requests.Count -eq 1) "Missing roles must trigger one update."
    $updated = @($requests[0].Body.appRoles)
    foreach ($role in $gatewayAppRoles) {
        Assert-True ($role.value -cin $updated.value) "Missing role $($role.value) was not added."
    }
    Assert-True ($updated.Count -eq (3 + @($initialRoles | Where-Object { $_.value -eq "Custom.Use" }).Count)) "Unexpected roles were added or removed."
}
Write-Host "PASS: Partial and empty role sets receive all missing gateway roles."

$requests.Clear()
$existingApp = @([pscustomobject]@{ appId = "fixture-client"; id = "fixture-app"; appRoles = @() })
$script:failUpdate = $true
$failed = $false
try {
    Invoke-Expression $registrationSource
} catch {
    if ($_.Exception.Message -notlike "*Failed to update app roles*") {
        throw
    }
    $failed = $true
}
Assert-True $failed "A failed role update must stop setup."
Assert-True (-not (Test-Path -LiteralPath $requests[0].BodyFile)) "Failed PATCH temporary file was not removed."
Write-Host "PASS: Graph update failures stop setup and remove temporary files."
