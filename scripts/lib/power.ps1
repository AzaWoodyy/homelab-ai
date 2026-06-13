function Get-HomelabPowerShellExecutablePath {
    $command = Get-Command "powershell.exe" -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    return (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")
}

function ConvertTo-HomelabEncodedPowerShellCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
}

function Get-HomelabDelayedSleepCommand {
    param(
        [int]$DelaySeconds = 10
    )

    return @"
Start-Sleep -Seconds $DelaySeconds
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class HomelabPowerNativeMethods
{
    [DllImport("powrprof.dll", SetLastError = true)]
    public static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);
}
'@
[void][HomelabPowerNativeMethods]::SetSuspendState(`$false, `$false, `$false)
"@
}

function Get-HomelabDelayedShutdownCommand {
    param(
        [int]$DelaySeconds = 10
    )

    return "Start-Sleep -Seconds $DelaySeconds; & shutdown.exe /s /t 0"
}

function Start-HomelabDelayedPowerAction {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("sleep", "shutdown")]
        [string]$ActionName,

        [int]$DelaySeconds = 10
    )

    $command = switch ($ActionName) {
        "sleep" { Get-HomelabDelayedSleepCommand -DelaySeconds $DelaySeconds }
        "shutdown" { Get-HomelabDelayedShutdownCommand -DelaySeconds $DelaySeconds }
    }

    $powershellPath = Get-HomelabPowerShellExecutablePath
    $encodedCommand = ConvertTo-HomelabEncodedPowerShellCommand -Command $command

    Start-Process -FilePath $powershellPath -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-EncodedCommand",
        $encodedCommand
    ) -WindowStyle Hidden | Out-Null
}

function Invoke-HomelabGracefulPowerAction {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("sleep", "shutdown")]
        [string]$ActionName,

        [int]$DelaySeconds = 10
    )

    $powerLabel = switch ($ActionName) {
        "sleep" { "sleep" }
        "shutdown" { "shutdown" }
    }

    Write-Log "Stopping the homelab stack before $powerLabel..." "STEP"
    $previousLogOverride = $env:HOMELAB_LOG_PATH
    $currentLogPath = Get-CurrentLogPath

    if (-not [string]::IsNullOrWhiteSpace($currentLogPath)) {
        $env:HOMELAB_LOG_PATH = $currentLogPath
    }

    try {
        & (Join-Path $script:HomelabRoot "scripts\stop.ps1")
    }
    finally {
        if ([string]::IsNullOrWhiteSpace($previousLogOverride)) {
            Remove-Item Env:HOMELAB_LOG_PATH -ErrorAction SilentlyContinue
        }
        else {
            $env:HOMELAB_LOG_PATH = $previousLogOverride
        }
    }

    Write-Log "The homelab stack is stopped. Scheduling Windows $powerLabel in $DelaySeconds seconds." "OK"
    Start-HomelabDelayedPowerAction -ActionName $ActionName -DelaySeconds $DelaySeconds
    Write-Log "Windows $powerLabel has been queued." "OK"
}
