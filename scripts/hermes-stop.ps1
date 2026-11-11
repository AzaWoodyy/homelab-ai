. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "hermes-stop"

$config = Get-HomelabConfig

Stop-HermesGateway -Config $config
