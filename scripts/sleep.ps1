. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "sleep"

Invoke-HomelabGracefulPowerAction -ActionName "sleep"
