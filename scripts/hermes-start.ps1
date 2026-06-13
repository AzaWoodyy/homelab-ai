. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "hermes-start"

$config = Get-HomelabConfig

Start-HermesGateway -Config $config
