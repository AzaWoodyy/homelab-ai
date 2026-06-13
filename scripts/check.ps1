param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$failures = New-Object System.Collections.Generic.List[string]

function Write-CheckLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "STEP", "OK", "ERROR")]
        [string]$Level = "INFO"
    )

    $color = switch ($Level) {
        "STEP" { "Cyan" }
        "OK" { "Green" }
        "ERROR" { "Red" }
        default { "Gray" }
    }

    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Get-GitTrackedFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $files = @(& git -C $root ls-files -- $Pattern 2>$null)

    if ($LASTEXITCODE -eq 0) {
        return @($files | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }

    return @()
}

function Add-CheckFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $failures.Add($Message) | Out-Null
    Write-CheckLog $Message "ERROR"
}

Write-CheckLog "Parsing tracked PowerShell scripts..." "STEP"
$powerShellFiles = @(Get-GitTrackedFiles -Pattern "*.ps1")

if ($powerShellFiles.Count -eq 0) {
    $powerShellFiles = @(
        Get-ChildItem -LiteralPath $PSScriptRoot -Filter "*.ps1" -Recurse -File |
            ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_.FullName) }
    )
}

foreach ($relativePath in $powerShellFiles) {
    $path = Join-Path $root $relativePath
    $tokens = $null
    $parseErrors = $null

    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors) | Out-Null

    foreach ($parseError in @($parseErrors)) {
        Add-CheckFailure "${relativePath}:$($parseError.Extent.StartLineNumber): $($parseError.Message)"
    }
}

if ($failures.Count -eq 0) {
    Write-CheckLog "PowerShell parse checks passed." "OK"
}

Write-CheckLog "Validating config JSON files..." "STEP"
$jsonFiles = @(Get-GitTrackedFiles -Pattern "config/*.json")

if ($jsonFiles.Count -eq 0) {
    $jsonFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $root "config") -Filter "*.json" -File |
            ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_.FullName) }
    )
}

foreach ($relativePath in $jsonFiles) {
    $path = Join-Path $root $relativePath

    try {
        Get-Content -Raw -LiteralPath $path | ConvertFrom-Json | Out-Null
    }
    catch {
        Add-CheckFailure "${relativePath}: $($_.Exception.Message)"
    }
}

if ($failures.Count -eq 0) {
    Write-CheckLog "Config JSON validation passed." "OK"
}

Write-CheckLog "Running manager UI checks..." "STEP"
$uiRoot = Join-Path $root "scripts\manager-ui"
Push-Location $uiRoot

try {
    & npm.cmd run check

    if ($LASTEXITCODE -ne 0) {
        Add-CheckFailure "Manager UI checks failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

if ($failures.Count -gt 0) {
    Write-CheckLog "$($failures.Count) check failure(s)." "ERROR"
    exit 1
}

Write-CheckLog "All checks passed." "OK"
