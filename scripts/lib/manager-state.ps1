function Get-HomelabManagerTaskName {
    return "\Homelab AI Manager"
}

function Get-HomelabManagerTaskNameCandidates {
    return @(
        (Get-HomelabManagerTaskName),
        "Homelab AI Manager"
    )
}

function Get-ManagerStateRoot {
    return Join-Path $script:HomelabRoot "state\manager"
}

function Ensure-ManagerStateRoot {
    $stateRoot = Get-ManagerStateRoot

    if (-not (Test-Path -LiteralPath $stateRoot)) {
        New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    }

    $jobsRoot = Join-Path $stateRoot "jobs"

    if (-not (Test-Path -LiteralPath $jobsRoot)) {
        New-Item -ItemType Directory -Path $jobsRoot -Force | Out-Null
    }

    return $stateRoot
}

function Get-ManagerJobsRoot {
    return Join-Path (Ensure-ManagerStateRoot) "jobs"
}

function Get-ManagerLockPath {
    return Join-Path (Ensure-ManagerStateRoot) "manager-lock.json"
}

function Get-ManagerCurrentJobPath {
    return Join-Path (Ensure-ManagerStateRoot) "current-job.json"
}

function Get-ManagerLastJobPath {
    return Join-Path (Ensure-ManagerStateRoot) "last-job.json"
}

function Get-ManagerHistoryPath {
    return Join-Path (Ensure-ManagerStateRoot) "job-history.json"
}

function Get-ManagerSessionsPath {
    return Join-Path (Ensure-ManagerStateRoot) "sessions.json"
}

function Get-ManagerPendingApplyPath {
    return Join-Path (Ensure-ManagerStateRoot) "pending-apply.json"
}

function Get-ManagerSummaryCachePath {
    return Join-Path (Ensure-ManagerStateRoot) "summary-cache.json"
}

function Get-ManagerSummaryRefreshLockPath {
    return Join-Path (Ensure-ManagerStateRoot) "summary-refresh-lock.json"
}

function Get-ManagerPidPath {
    return Join-Path (Ensure-ManagerStateRoot) "manager.pid"
}

function Get-ManagerRuntimeInfoPath {
    return Join-Path (Ensure-ManagerStateRoot) "runtime.json"
}

function Get-ManagerJobLogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId
    )

    return Join-Path (Get-ManagerJobsRoot) "$JobId.log"
}

function Get-ManagerRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return Get-HomelabRelativePath -RootPath $script:HomelabRoot -Path $Path
}

function Get-ManagerTimestamp {
    return (Get-Date).ToString("o")
}

function Get-HomelabManagerCurrentJob {
    $job = Read-JsonFile -Path (Get-ManagerCurrentJobPath) -AllowMissing

    if ($null -eq $job) {
        return $null
    }

    $status = [string]$job.status

    if ($status -notin @("queued", "running")) {
        return $job
    }

    $managerLock = Get-HomelabManagerLockInfo

    if ($null -eq $managerLock) {
        return $job
    }

    $jobStartedAt = [datetime]::MinValue
    $managerStartedAt = [datetime]::MinValue
    $jobStartedAtText = [string]$(if ($null -ne $job.started_at) { $job.started_at } else { $job.created_at })
    $managerStartedAtText = [string]$managerLock.started_at

    if (
        [datetime]::TryParse($jobStartedAtText, [ref]$jobStartedAt) -and
        [datetime]::TryParse($managerStartedAtText, [ref]$managerStartedAt) -and
        $jobStartedAt -lt $managerStartedAt
    ) {
        $job.status = "failed"
        $job.finished_at = Get-ManagerTimestamp
        $job.exit_code = 1

        if ([string]::IsNullOrWhiteSpace([string]$job.error)) {
            $job.error = "This manager job was left running by an older manager process and has been marked stale."
        }

        Save-HomelabManagerLastJob -Job $job
        Clear-HomelabManagerCurrentJob
        return $null
    }

    return $job
}

function Save-HomelabManagerCurrentJob {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Job
    )

    Write-JsonFile -Path (Get-ManagerCurrentJobPath) -Value $Job
}

function Clear-HomelabManagerCurrentJob {
    Remove-FileIfPresent -Path (Get-ManagerCurrentJobPath)
}

function Get-HomelabManagerLastJob {
    return Read-JsonFile -Path (Get-ManagerLastJobPath) -AllowMissing
}

function Save-HomelabManagerLastJob {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Job
    )

    Write-JsonFile -Path (Get-ManagerLastJobPath) -Value $Job
}

function Get-HomelabManagerJobHistory {
    $history = Read-JsonFile -Path (Get-ManagerHistoryPath) -AllowMissing

    if ($null -eq $history) {
        return @()
    }

    $normalized = New-Object System.Collections.Generic.List[object]
    $changed = $false

    foreach ($job in @($history)) {
        if ($null -eq $job) {
            continue
        }

        $errorText = [string](Get-HomelabObjectPropertyValue -InputObject $job -Name "error" -DefaultValue "")

        if (-not [string]::IsNullOrWhiteSpace($errorText) -and $errorText.Length -gt 16000) {
            $job.error = $errorText.Substring(0, 16000) + "... [truncated]"
            $changed = $true
        }

        $normalized.Add($job) | Out-Null
    }

    if ($changed) {
        Save-HomelabManagerJobHistory -History $normalized.ToArray()
    }

    return $normalized.ToArray()
}

function Save-HomelabManagerJobHistory {
    param(
        [object[]]$History = @()
    )

    Write-JsonFile -Path (Get-ManagerHistoryPath) -Value @($History)
}

function Add-HomelabManagerJobHistoryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Job
    )

    $history = New-Object System.Collections.Generic.List[object]
    $history.Add($Job)

    foreach ($item in (Get-HomelabManagerJobHistory | Select-Object -First 19)) {
        $history.Add($item)
    }

    Save-HomelabManagerJobHistory -History $history.ToArray()
    Save-HomelabManagerLastJob -Job $Job
}

function Get-HomelabManagerJobLogTail {
    param(
        [string]$LogPath,
        [int]$Tail = 120
    )

    if ([string]::IsNullOrWhiteSpace($LogPath) -or -not (Test-Path -LiteralPath $LogPath)) {
        return @()
    }

    return @(Get-Content -LiteralPath $LogPath -Tail $Tail)
}

function Add-HomelabManagerJobTail {
    param(
        [object]$Job,

        [int]$Tail = 120
    )

    if ($null -eq $Job) {
        return $null
    }

    $tailCount = [int]$Tail
    $logTail = if ($tailCount -gt 0) {
        Get-HomelabManagerJobLogTail -LogPath ([string]$Job.log_path) -Tail $tailCount
    }
    else {
        @()
    }

    return [ordered]@{
        id                = $Job.id
        action            = $Job.action
        status            = $Job.status
        created_at        = $Job.created_at
        started_at        = $Job.started_at
        finished_at       = $Job.finished_at
        exit_code         = $Job.exit_code
        log_path          = $Job.log_path
        log_relative_path = $Job.log_relative_path
        error             = $Job.error
        log_tail          = @($logTail)
    }
}

function Get-HomelabManagerPendingApplyState {
    return Read-JsonFile -Path (Get-ManagerPendingApplyPath) -AllowMissing
}

function Save-HomelabManagerPendingApplyState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    Write-JsonFile -Path (Get-ManagerPendingApplyPath) -Value $State
}

function Clear-HomelabManagerPendingApplyState {
    Remove-FileIfPresent -Path (Get-ManagerPendingApplyPath)
}

function Get-HomelabManagerSessions {
    $sessions = Read-JsonFile -Path (Get-ManagerSessionsPath) -AllowMissing

    if ($null -eq $sessions) {
        return @()
    }

    return @($sessions)
}

function Save-HomelabManagerSessions {
    param(
        [object[]]$Sessions = @()
    )

    Write-JsonFile -Path (Get-ManagerSessionsPath) -Value @($Sessions)
}
