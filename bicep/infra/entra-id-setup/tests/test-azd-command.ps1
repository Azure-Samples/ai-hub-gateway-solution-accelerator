$ErrorActionPreference = "Stop"

$setupPath = Join-Path $PSScriptRoot "..\setup.ps1"
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $setupPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Setup script has syntax errors: $($parseErrors.Message -join '; ')"
}

$helper = $ast.EndBlock.Statements | Where-Object {
    $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $_.Name -in @("Invoke-SetupCommand", "Invoke-AzdCommand")
}
if (-not $helper) {
    throw "Could not locate azd command helper."
}
foreach ($definition in $helper) { Invoke-Expression $definition.Extent.Text }

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

# Use a real native process to reproduce Windows PowerShell's stderr handling without Azure calls.
$script:mode = "success"
$script:calls = [System.Collections.Generic.List[string]]::new()
function azd {
    $script:calls.Add(($args -join " "))
    if ($script:mode -eq "failure") {
        & $env:ComSpec /d /c 'echo fixture failure 1>&2&echo untrusted-output&exit /b 7'
    } elseif ($args[1] -eq "get-value") {
        & $env:ComSpec /d /c 'echo Update available: fixture notice 1>&2&echo fixture-value&exit /b 0'
    } else {
        & $env:ComSpec /d /c 'echo Update available: fixture notice 1>&2&exit /b 0'
    }
}

$PSNativeCommandUseErrorActionPreference = $true
$result = @(Invoke-AzdCommand -Arguments @("env", "get-value", "AZURE_ENV_NAME") 3>&1)
$stdout = @($result | Where-Object { $_ -is [string] })
$warnings = @($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
Assert-True ($stdout.Count -eq 1 -and $stdout[0] -eq "fixture-value") "Update notices must not contaminate stdout."
Assert-True ($warnings.Count -eq 1 -and $warnings[0].Message -like "*Update available: fixture notice*") "Native diagnostics must remain visible as warnings."
Assert-True ($ErrorActionPreference -eq "Stop") "Caller error handling changed."
Assert-True $PSNativeCommandUseErrorActionPreference "Caller native-error preference changed."
Write-Host "PASS: Native update notices do not terminate successful reads or contaminate values."

$result = @(Invoke-AzdCommand -Arguments @("env", "set", "ENTRA_CLIENT_SECRET", "fixture-secret") 3>&1)
Assert-True (@($result | Where-Object { $_ -is [string] }).Count -eq 0) "Successful writes must not return diagnostic output."
Assert-True ($calls[$calls.Count - 1] -eq "env set ENTRA_CLIENT_SECRET fixture-secret") "Write arguments changed."
Write-Host "PASS: Environment writes tolerate successful stderr notices."

$script:mode = "failure"
foreach ($arguments in @(
    @("env", "get-value", "AZURE_ENV_NAME"),
    @("env", "set", "ENTRA_CLIENT_SECRET", "fixture-secret")
)) {
    $failed = $false
    $result = @()
    try {
        $result = @(Invoke-AzdCommand -Arguments $arguments 3>$null)
    } catch {
        Assert-True ($_.Exception.Message -like "azd env * failed (exit code 7).") "Unexpected command failure."
        Assert-True ($_.Exception.Message -notlike "*fixture-secret*") "Command error exposed an argument value."
        $failed = $true
    }
    Assert-True $failed "A required azd command failure must stop setup."
    Assert-True ($result.Count -eq 0) "Failed commands must not return partial stdout."
    Assert-True ($ErrorActionPreference -eq "Stop") "Error handling was not restored after failure."
}
Write-Host "PASS: Required read and write failures terminate without leaking argument values."

$result = @(Invoke-AzdCommand -Arguments @("env", "get-value", "APIM_NAME") -AllowFailure 3>&1)
Assert-True (@($result | Where-Object { $_ -is [string] }).Count -eq 0) "Optional lookup failures must return no value."
Assert-True (@($result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count -eq 2) "Optional lookup failures must report diagnostics and exit status."
Write-Host "PASS: Optional lookup failures are reported and permit discovery fallbacks."

$script:mode = "success"
$script:calls.Clear()
$EnvironmentName = ""
$KeyVaultName = ""
$ApimResourceGroup = ""
$ApimName = ""
$resolution = $ast.EndBlock.Statements | Where-Object {
    $_ -is [System.Management.Automation.Language.IfStatementAst] -and
    $_.Clauses[0].Item1.Extent.Text -like '[[]string[]]::IsNullOrWhiteSpace(*)'
} | Select-Object -First 4
Assert-True (@($resolution).Count -eq 4) "Could not locate parameter resolution statements."
foreach ($statement in $resolution) {
    Invoke-Expression $statement.Extent.Text 3>$null
}
foreach ($value in @($EnvironmentName, $KeyVaultName, $ApimResourceGroup, $ApimName)) {
    Assert-True ($value -eq "fixture-value") "Parameter resolution failed with native stderr notices."
}
Assert-True ($calls.Count -eq 4) "Unexpected parameter resolution commands."
Write-Host "PASS: All auto-detected setup parameters resolve despite update notices."

$script:calls.Clear()
$EnvironmentName = "explicit-environment"
$KeyVaultName = "explicit-vault"
$ApimResourceGroup = "explicit-rg"
$ApimName = "explicit-apim"
foreach ($statement in $resolution) {
    Invoke-Expression $statement.Extent.Text
}
Assert-True ($calls.Count -eq 0) "Explicit parameters must not trigger azd lookups."
Write-Host "PASS: Explicit parameters still bypass environment lookups."
