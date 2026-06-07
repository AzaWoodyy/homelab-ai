param(
    [Parameter(Mandatory = $true)]
    [string]$ActionName,

    [Parameter(Mandatory = $true)]
    [string]$JobId,

    [int]$ManagerPid = 0
)

. (Join-Path $PSScriptRoot "common.ps1")

$jobLogPath = Get-ManagerJobLogPath -JobId $JobId
$env:HOMELAB_LOG_PATH = $jobLogPath

Initialize-HomelabScript -ScriptName "manager-job-$ActionName"
Write-Log "Starting manager action '$ActionName'." "STEP"
[void](Update-HomelabManagerJobState -JobId $JobId -Status "running")

$exitCode = 0
$errorMessage = $null

try {
    $descriptor = Get-HomelabManagerActionDescriptor -ActionName $ActionName

    if ([string]$descriptor.kind -eq "script") {
        & $descriptor.script_path
    }
    elseif ($ActionName -eq "manager-stop") {
        $config = Get-HomelabConfig

        try {
            Disable-TailscaleManagementHttps -Config $config
            Write-Log "Management Tailscale HTTPS mapping disabled." "OK"
        }
        catch {
            Write-Log "Management Tailscale HTTPS disable skipped: $($_.Exception.Message)" "WARN"
        }

        if ($ManagerPid -gt 0) {
            Write-Log "Stopping manager process $ManagerPid." "STEP"
            Stop-HomelabManagerProcess -ProcessId $ManagerPid
        }
    }
    elseif ($ActionName -eq "manager-restart") {
        $config = Get-HomelabConfig

        if ($ManagerPid -gt 0) {
            Write-Log "Stopping current manager process $ManagerPid." "STEP"
            Stop-HomelabManagerProcess -ProcessId $ManagerPid
            Start-Sleep -Seconds 2
        }

        Write-Log "Starting new manager process." "STEP"
        [void](Start-HomelabManagerDetached -Restart)
        Wait-ForHomelabManager -Config $config -TimeoutSeconds 20

        try {
            Enable-TailscaleManagementHttps -Config $config
            Write-Log "Management Tailscale HTTPS mapping enabled." "OK"
        }
        catch {
            Write-Log "Management Tailscale HTTPS enable skipped: $($_.Exception.Message)" "WARN"
        }
    }
}
catch {
    $exitCode = 1
    $errorMessage = $_.Exception.Message
    Write-Log "Manager action '$ActionName' failed: $errorMessage" "ERROR"
}
finally {
    Remove-Item Env:HOMELAB_LOG_PATH -ErrorAction SilentlyContinue
}

if ($exitCode -eq 0) {
    Write-Log "Manager action '$ActionName' completed." "OK"
    [void](Update-HomelabManagerJobState -JobId $JobId -Status "completed" -ExitCode 0)
}
else {
    [void](Update-HomelabManagerJobState -JobId $JobId -Status "failed" -ExitCode $exitCode -ErrorMessage $errorMessage)
    exit $exitCode
}
