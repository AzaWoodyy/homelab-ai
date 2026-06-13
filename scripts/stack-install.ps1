param(
    [switch]$StartNow
)

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "stack-install"

function Get-StackStartupTaskName {
    return "\Homelab AI Stack"
}

function Get-StackStartupExecutablePath {
    $command = Get-Command "powershell.exe" -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    return (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")
}

Assert-TailscaleAdminAccess

$startupScriptPath = Join-Path $PSScriptRoot "stack-startup.ps1"
$powershellPath = Get-StackStartupExecutablePath
$taskCommand = '"' + $powershellPath + '" -NoProfile -ExecutionPolicy Bypass -File "' + $startupScriptPath + '"'
$taskName = Get-StackStartupTaskName

Write-Log "Registering Homelab stack startup scheduled task..." "STEP"
$result = Invoke-NativeCommand -FilePath "schtasks.exe" -Arguments @(
    "/Create",
    "/TN",
    $taskName,
    "/SC",
    "ONSTART",
    "/RU",
    "SYSTEM",
    "/RL",
    "HIGHEST",
    "/DELAY",
    "0000:30",
    "/TR",
    $taskCommand,
    "/F"
)

if ($result.ExitCode -ne 0) {
    throw (($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim())
}

Write-Log "Homelab stack startup scheduled task registered." "OK"

if ($StartNow) {
    Write-Log "Starting Homelab stack startup task now..." "STEP"
    $runResult = Invoke-NativeCommand -FilePath "schtasks.exe" -Arguments @("/Run", "/TN", $taskName)

    if ($runResult.ExitCode -ne 0) {
        throw (($runResult.StdErr + [Environment]::NewLine + $runResult.StdOut).Trim())
    }

    Write-Log "Homelab stack startup task launched." "OK"
}
