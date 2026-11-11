function Get-HomelabManagerActionDescriptor {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ActionName
    )

    $scriptPath = switch ($ActionName) {
        "start" { Join-Path $script:HomelabRoot "scripts\start.ps1" }
        "stop" { Join-Path $script:HomelabRoot "scripts\stop.ps1" }
        "setup" { Join-Path $script:HomelabRoot "scripts\setup.ps1" }
        "refresh-models" { Join-Path $script:HomelabRoot "scripts\refresh-models.ps1" }
        "test" { Join-Path $script:HomelabRoot "scripts\test.ps1" }
        "sleep" { Join-Path $script:HomelabRoot "scripts\sleep.ps1" }
        "shutdown" { Join-Path $script:HomelabRoot "scripts\shutdown.ps1" }
        "hermes-start" { Join-Path $script:HomelabRoot "scripts\hermes-start.ps1" }
        "hermes-stop" { Join-Path $script:HomelabRoot "scripts\hermes-stop.ps1" }
        "hermes-restart" { Join-Path $script:HomelabRoot "scripts\hermes-restart.ps1" }
        default { $null }
    }

    if ($null -ne $scriptPath) {
        return [ordered]@{
            action_name = $ActionName
            kind        = "script"
            script_path = $scriptPath
        }
    }

    if ($ActionName -in @("manager-stop", "manager-restart")) {
        return [ordered]@{
            action_name = $ActionName
            kind        = "manager"
        }
    }

    throw "Unsupported action '$ActionName'."
}

function Get-HomelabManagerRecommendedActions {
    param(
        [bool]$ConfigChanged,
        [string[]]$AddedModels = @(),
        [string[]]$RemovedModels = @()
    )

    $actions = New-Object System.Collections.Generic.List[string]
    $modelsChanged = (@($AddedModels).Count -gt 0 -or @($RemovedModels).Count -gt 0)

    if ($ConfigChanged -or @($AddedModels).Count -gt 0) {
        $actions.Add("setup")
    }

    if ($ConfigChanged) {
        $config = Get-HomelabConfig
        $stackIsRunning = (Get-OpenWebUiHealth -Config $config) -in @("healthy", "running")

        if ($stackIsRunning) {
            $actions.Add("stop")
            $actions.Add("start")
        }
    }

    if ($ConfigChanged -or $modelsChanged) {
        $actions.Add("test")
    }

    return $actions.ToArray()
}

function Set-HomelabManagerPendingApplyState {
    param(
        [bool]$ConfigChanged,
        [bool]$ModelsChanged,
        [string[]]$AddedModels = @(),
        [string[]]$RemovedModels = @()
    )

    if (-not $ConfigChanged -and -not $ModelsChanged) {
        return Get-HomelabManagerPendingApplyState
    }

    $previous = Get-HomelabManagerPendingApplyState
    $completedActions = @()

    if ($null -ne $previous -and $null -ne $previous.completed_actions) {
        $completedActions = @($previous.completed_actions)
    }

    $requiredActions = Get-HomelabManagerRecommendedActions -ConfigChanged $ConfigChanged -AddedModels @($AddedModels) -RemovedModels @($RemovedModels)
    $remainingActions = @($requiredActions | Where-Object { $_ -notin $completedActions })

    $state = [ordered]@{
        has_pending       = $true
        updated_at        = Get-ManagerTimestamp
        config_changed    = $ConfigChanged
        models_changed    = $ModelsChanged
        added_models      = @($AddedModels)
        removed_models    = @($RemovedModels)
        required_actions  = @($requiredActions)
        completed_actions = @($completedActions | Where-Object { $_ -in $requiredActions })
        remaining_actions = @($remainingActions)
    }

    Save-HomelabManagerPendingApplyState -State $state
    return $state
}

function Complete-HomelabManagerPendingAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ActionName
    )

    $state = Get-HomelabManagerPendingApplyState

    if ($null -eq $state -or $ActionName -notin @($state.required_actions)) {
        return $state
    }

    $completedActions = @($state.completed_actions)

    if ($ActionName -notin $completedActions) {
        $completedActions += $ActionName
    }

    $remainingActions = @($state.required_actions | Where-Object { $_ -notin $completedActions })

    if ($remainingActions.Count -eq 0) {
        Clear-HomelabManagerPendingApplyState
        return $null
    }

    $updatedState = [ordered]@{
        has_pending       = $true
        updated_at        = Get-ManagerTimestamp
        config_changed    = [bool]$state.config_changed
        models_changed    = [bool]$state.models_changed
        added_models      = @($state.added_models)
        removed_models    = @($state.removed_models)
        required_actions  = @($state.required_actions)
        completed_actions = @($completedActions)
        remaining_actions = @($remainingActions)
    }

    Save-HomelabManagerPendingApplyState -State $updatedState
    return $updatedState
}

function Start-HomelabManagerActionJob {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ActionName
    )

    $currentJob = Get-HomelabManagerCurrentJob

    if ($null -ne $currentJob -and [string]$currentJob.status -in @("queued", "running")) {
        throw "Another manager action is already running."
    }

    $descriptor = Get-HomelabManagerActionDescriptor -ActionName $ActionName
    $jobId = [guid]::NewGuid().ToString("n")
    $logPath = Get-ManagerJobLogPath -JobId $jobId
    $job = [ordered]@{
        id                 = $jobId
        action             = $ActionName
        status             = "queued"
        created_at         = Get-ManagerTimestamp
        started_at         = $null
        finished_at        = $null
        exit_code          = $null
        log_path           = $logPath
        log_relative_path  = Get-ManagerRelativePath -Path $logPath
        error              = $null
    }

    Save-HomelabManagerCurrentJob -Job $job

    $powershellPath = Get-HomelabManagerExecutablePath
    $runnerScriptPath = Join-Path $script:HomelabRoot "scripts\manager-job-runner.ps1"
    $managerPid = $PID
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $runnerScriptPath,
        "-ActionName",
        $ActionName,
        "-JobId",
        $jobId,
        "-ManagerPid",
        "$managerPid"
    )

    Start-Process -FilePath $powershellPath -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    return $job
}

function Update-HomelabManagerJobState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [int]$ExitCode = $null,

        [string]$ErrorMessage = $null
    )

    $job = Get-HomelabManagerCurrentJob

    if ($null -eq $job -or [string]$job.id -ne $JobId) {
        $job = Get-HomelabManagerLastJob
    }

    if ($null -eq $job) {
        $job = [ordered]@{
            id = $JobId
        }
    }

    $job.status = $Status

    if ($Status -eq "running" -and $null -eq $job.started_at) {
        $job.started_at = Get-ManagerTimestamp
    }

    if ($Status -in @("completed", "failed")) {
        $job.finished_at = Get-ManagerTimestamp
        $job.exit_code = $ExitCode
        $job.error = $ErrorMessage
    }

    Save-HomelabManagerCurrentJob -Job $job

    if ($Status -in @("completed", "failed")) {
        Add-HomelabManagerJobHistoryEntry -Job $job
        Clear-HomelabManagerCurrentJob

        if ($Status -eq "completed") {
            [void](Complete-HomelabManagerPendingAction -ActionName ([string]$job.action))
        }
    }

    return $job
}

function Get-HomelabManagerJobsSnapshot {
    param(
        [int]$Tail = 120,

        [int]$HistoryLimit = 20
    )

    $currentJob = Add-HomelabManagerJobTail -Job (Get-HomelabManagerCurrentJob) -Tail $Tail
    $lastJob = Add-HomelabManagerJobTail -Job (Get-HomelabManagerLastJob) -Tail $Tail
    $history = @()

    foreach ($job in (Get-HomelabManagerJobHistory | Select-Object -First $HistoryLimit)) {
        $history += (Add-HomelabManagerJobTail -Job $job -Tail $Tail)
    }

    return [ordered]@{
        current       = $currentJob
        latest        = $lastJob
        history       = @($history)
        pending_apply = Get-HomelabManagerPendingApplyState
    }
}

function Get-HomelabManagerFastJobsSnapshot {
    $currentJob = Add-HomelabManagerJobTail -Job (Get-HomelabManagerCurrentJob) -Tail 0
    $lastJob = Add-HomelabManagerJobTail -Job (Get-HomelabManagerLastJob) -Tail 0

    return [ordered]@{
        current       = $currentJob
        latest        = $lastJob
        history       = @()
        pending_apply = Get-HomelabManagerPendingApplyState
    }
}
