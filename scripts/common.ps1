Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:HomelabRoot = Split-Path $PSScriptRoot -Parent
$script:CurrentLogPath = $null

$script:HomelabScriptModules = @(
    "logging.ps1",
    "runtime.ps1",
    "models.ps1",
    "config.ps1",
    "dependencies.ps1",
    "ollama.ps1",
    "docker.ps1",
    "http.ps1",
    "tailscale.ps1"
)

foreach ($moduleName in $script:HomelabScriptModules) {
    $modulePath = Join-Path (Join-Path $PSScriptRoot "lib") $moduleName

    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Required script module not found: $modulePath"
    }

    . $modulePath
}
