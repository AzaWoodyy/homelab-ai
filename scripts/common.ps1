Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:HomelabRoot = Split-Path $PSScriptRoot -Parent
$script:CurrentLogPath = $null

$script:HomelabScriptModules = @(
    "logging.ps1",
    "runtime.ps1",
    "utilities.ps1",
    "power.ps1",
    "models.ps1",
    "config.ps1",
    "dependencies.ps1",
    "ollama.ps1",
    "docker.ps1",
    "openwebui.ps1",
    "hermes.ps1",
    "http.ps1",
    "tailscale.ps1",
    "manager-state.ps1",
    "manager-process.ps1",
    "manager-jobs.ps1",
    "manager-auth.ps1",
    "manager-http.ps1",
    "manager-probes.ps1",
    "manager-summary.ps1",
    "manager-api.ps1"
)

foreach ($moduleName in $script:HomelabScriptModules) {
    $modulePath = Join-Path (Join-Path $PSScriptRoot "lib") $moduleName

    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Required script module not found: $modulePath"
    }

    . $modulePath
}
