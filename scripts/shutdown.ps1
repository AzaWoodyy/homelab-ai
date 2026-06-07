. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "shutdown"

Invoke-HomelabGracefulPowerAction -ActionName "shutdown"
