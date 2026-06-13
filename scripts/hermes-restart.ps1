. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "hermes-restart"

$config = Get-HomelabConfig

Restart-HermesGateway -Config $config
