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

function Get-HomelabManagerLockInfo {
    $lockPath = Get-ManagerLockPath
    $lockInfo = Read-JsonFile -Path $lockPath -AllowMissing

    if ($null -eq $lockInfo) {
        return $null
    }

    if (-not (Test-ProcessAlive -Id ([int]$lockInfo.pid))) {
        Remove-FileIfPresent -Path $lockPath
        return $null
    }

    return $lockInfo
}

function Write-HomelabManagerLockInfo {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ProcessId,

        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    $lockInfo = [ordered]@{
        pid        = $ProcessId
        port       = $Port
        started_at = Get-ManagerTimestamp
    }

    Write-JsonFile -Path (Get-ManagerLockPath) -Value $lockInfo
    [System.IO.File]::WriteAllText((Get-ManagerPidPath), "$ProcessId`n", [System.Text.UTF8Encoding]::new($false))
    Write-JsonFile -Path (Get-ManagerRuntimeInfoPath) -Value ([ordered]@{
        pid         = $ProcessId
        local_url   = "http://127.0.0.1:$Port"
        started_at  = $lockInfo.started_at
        state_root  = Get-ManagerStateRoot
    })
}

function Remove-HomelabManagerLockInfo {
    Remove-FileIfPresent -Path (Get-ManagerLockPath)
    Remove-FileIfPresent -Path (Get-ManagerPidPath)
    Remove-FileIfPresent -Path (Get-ManagerRuntimeInfoPath)
}

function Test-HomelabManagerRunning {
    return $null -ne (Get-HomelabManagerLockInfo)
}

function Get-HomelabManagerLocalUrl {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return "http://127.0.0.1:$($Config.management_port)"
}

function Get-HomelabManagerRemoteUrl {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$NodeInfo
    )

    return "https://$($NodeInfo.DnsName):$($Config.management_tailscale_https_port)"
}

function Get-HomelabManagerRequestHandlerScript {
    return {
        param($Context, $RootPath)

        try {
            . (Join-Path $RootPath "scripts\common.ps1")
            Handle-HomelabManagerRequest -Context $Context
        }
        catch {
            try {
                $payload = [ordered]@{
                    error = "internal_error"
                    message = $_.Exception.Message
                }
                Send-JsonResponse -Response $Context.Response -StatusCode 500 -Value $payload
            }
            catch {
            }
        }
    }
}

function Get-HomelabManagerExecutablePath {
    $command = Get-Command "powershell.exe" -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    return (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")
}

function Start-HomelabManagerDetached {
    param(
        [switch]$Restart
    )

    $config = Get-HomelabConfig
    Assert-ManagementAdminSecretConfigured -Config $config

    if ((Test-HomelabManagerRunning) -and -not $Restart) {
        return Get-HomelabManagerLockInfo
    }

    $powershellPath = Get-HomelabManagerExecutablePath
    $serviceScriptPath = Join-Path $script:HomelabRoot "scripts\manager-service.ps1"
    $process = Start-Process -FilePath $powershellPath -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $serviceScriptPath) -WindowStyle Hidden -PassThru

    return [ordered]@{
        pid = $process.Id
    }
}

function Stop-HomelabManagerProcess {
    param(
        [int]$ProcessId
    )

    if ($ProcessId -le 0) {
        return
    }

    if (-not (Test-ProcessAlive -Id $ProcessId)) {
        return
    }

    Stop-Process -Id $ProcessId -Force
}

function Wait-ForHomelabManager {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $url = Get-HomelabManagerLocalUrl -Config $Config

    while ((Get-Date) -lt $deadline) {
        $response = Test-HttpEndpoint -Url $url -TimeoutSeconds 5

        if ($response.Ok) {
            return
        }

        Start-Sleep -Milliseconds 500
    }

    throw "Homelab manager did not become reachable at $url within $TimeoutSeconds seconds."
}

function Get-HomelabManagerScheduledTaskExpectedUser {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Get-HomelabManagerTaskLeafName {
    return (Get-HomelabManagerTaskName).TrimStart('\')
}

function Get-HomelabManagerTaskQuery {
    $expectedUser = Get-HomelabManagerScheduledTaskExpectedUser

    try {
        $scheduleService = New-Object -ComObject "Schedule.Service"
        $scheduleService.Connect()
        $rootFolder = $scheduleService.GetFolder("\")

        foreach ($taskName in @(Get-HomelabManagerTaskNameCandidates)) {
            $normalizedTaskName = [string]$taskName

            if (-not $normalizedTaskName.StartsWith("\")) {
                $normalizedTaskName = "\" + $normalizedTaskName
            }

            try {
                $task = $rootFolder.GetTask($normalizedTaskName)

                if ($null -ne $task) {
                    [xml]$taskXml = $task.Xml
                    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($taskXml.NameTable)
                    $namespaceManager.AddNamespace("t", "http://schemas.microsoft.com/windows/2004/02/mit/task")

                    $principalUserNode = $taskXml.SelectSingleNode("/t:Task/t:Principals/t:Principal/t:UserId", $namespaceManager)
                    $logonTypeNode = $taskXml.SelectSingleNode("/t:Task/t:Principals/t:Principal/t:LogonType", $namespaceManager)
                    $runLevelNode = $taskXml.SelectSingleNode("/t:Task/t:Principals/t:Principal/t:RunLevel", $namespaceManager)
                    $logonTriggerNode = $taskXml.SelectSingleNode("/t:Task/t:Triggers/t:LogonTrigger", $namespaceManager)
                    $bootTriggerNode = $taskXml.SelectSingleNode("/t:Task/t:Triggers/t:BootTrigger", $namespaceManager)

                    $principalUser = if ($null -ne $principalUserNode) { [string]$principalUserNode.InnerText } else { "" }
                    $logonType = if ($null -ne $logonTypeNode) { [string]$logonTypeNode.InnerText } else { "" }
                    $runLevel = if ($null -ne $runLevelNode) { [string]$runLevelNode.InnerText } else { "" }

                    $isExpectedRegistration = (
                        -not [string]::IsNullOrWhiteSpace($principalUser) -and
                        $principalUser -ieq $expectedUser -and
                        $null -ne $logonTriggerNode -and
                        $null -eq $bootTriggerNode -and
                        $logonType -ieq "InteractiveToken" -and
                        $runLevel -ieq "HighestAvailable"
                    )

                    return [pscustomobject]@{
                        Exists                 = $true
                        IsExpectedRegistration = $isExpectedRegistration
                        UserId                 = $principalUser
                        ExpectedUserId         = $expectedUser
                        LogonType              = $logonType
                        RunLevel               = $runLevel
                        HasLogonTrigger        = ($null -ne $logonTriggerNode)
                        HasBootTrigger         = ($null -ne $bootTriggerNode)
                        Raw                    = "Task Scheduler COM query matched $normalizedTaskName."
                        ExitCode               = 0
                    }
                }
            }
            catch {
            }
        }
    }
    catch {
    }

    return [pscustomobject]@{
        Exists                 = $false
        IsExpectedRegistration = $false
        UserId                 = ""
        ExpectedUserId         = $expectedUser
        LogonType              = ""
        RunLevel               = ""
        HasLogonTrigger        = $false
        HasBootTrigger         = $false
        Raw                    = "Task query failed for all candidates: $([string]::Join(', ', @(Get-HomelabManagerTaskNameCandidates)))."
        ExitCode               = 1
    }
}

function Test-HomelabManagerTaskRegistered {
    $taskQuery = Get-HomelabManagerTaskQuery
    return ($taskQuery.Exists -and $taskQuery.IsExpectedRegistration)
}

function Register-HomelabManagerScheduledTaskWithCom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PowerShellPath,

        [Parameter(Mandatory = $true)]
        [string]$StartScriptPath
    )

    $scheduleService = New-Object -ComObject "Schedule.Service"
    $scheduleService.Connect()
    $rootFolder = $scheduleService.GetFolder("\")
    $taskDefinition = $scheduleService.NewTask(0)
    $taskUser = Get-HomelabManagerScheduledTaskExpectedUser

    $taskDefinition.RegistrationInfo.Description = "Starts the Homelab AI manager for the signed-in user."
    $taskDefinition.Settings.Enabled = $true
    $taskDefinition.Settings.StartWhenAvailable = $true
    $taskDefinition.Settings.DisallowStartIfOnBatteries = $false
    $taskDefinition.Settings.StopIfGoingOnBatteries = $false

    $taskDefinition.Principal.UserId = $taskUser
    $taskDefinition.Principal.LogonType = 3
    $taskDefinition.Principal.RunLevel = 1

    $trigger = $taskDefinition.Triggers.Create(9)
    $trigger.Enabled = $true

    $action = $taskDefinition.Actions.Create(0)
    $action.Path = $PowerShellPath
    $action.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $StartScriptPath + '"'

    [void]$rootFolder.RegisterTaskDefinition((Get-HomelabManagerTaskLeafName), $taskDefinition, 6, $null, $null, 3, $null)
}

function Register-HomelabManagerScheduledTask {
    $startScriptPath = Join-Path $script:HomelabRoot "scripts\manager-start.ps1"
    $powershellPath = Get-HomelabManagerExecutablePath
    $taskCommand = '"' + $powershellPath + '" -NoProfile -ExecutionPolicy Bypass -File "' + $startScriptPath + '"'
    $taskName = Get-HomelabManagerTaskName
    $taskQuery = Get-HomelabManagerTaskQuery

    if ($taskQuery.Exists) {
        Unregister-HomelabManagerScheduledTask
    }

    $result = Invoke-NativeCommand -FilePath "schtasks.exe" -Arguments @(
        "/Create",
        "/TN",
        $taskName,
        "/SC",
        "ONLOGON",
        "/RL",
        "HIGHEST",
        "/IT",
        "/TR",
        $taskCommand,
        "/F"
    )

    if ($result.ExitCode -ne 0) {
        try {
            Register-HomelabManagerScheduledTaskWithCom -PowerShellPath $powershellPath -StartScriptPath $startScriptPath
        }
        catch {
            $message = (($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim())

            if (-not [string]::IsNullOrWhiteSpace($_.Exception.Message)) {
                $message = "$message$([Environment]::NewLine)$($_.Exception.Message)".Trim()
            }

            throw $message
        }
    }
}

function Unregister-HomelabManagerScheduledTaskWithCom {
    $scheduleService = New-Object -ComObject "Schedule.Service"
    $scheduleService.Connect()
    $rootFolder = $scheduleService.GetFolder("\")
    $rootFolder.DeleteTask((Get-HomelabManagerTaskLeafName), 0)
}

function Unregister-HomelabManagerScheduledTask {
    $taskName = Get-HomelabManagerTaskName
    $result = Invoke-NativeCommand -FilePath "schtasks.exe" -Arguments @("/Delete", "/TN", $taskName, "/F")

    $combinedOutput = (($result.StdOut + [Environment]::NewLine + $result.StdErr).Trim())

    if (
        $result.ExitCode -ne 0 -and
        $combinedOutput -notmatch "(?i)cannot find the file specified" -and
        $combinedOutput -notmatch "(?i)introuvable"
    ) {
        try {
            Unregister-HomelabManagerScheduledTaskWithCom
        }
        catch {
            throw $combinedOutput
        }
    }
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

function New-HomelabManagerSessionToken {
    return New-HomelabManagerRandomToken
}

function Convert-HomelabBase64Url {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    return [Convert]::ToBase64String($Bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function New-HomelabManagerRandomToken {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    return Convert-HomelabBase64Url -Bytes $bytes
}

function Get-HomelabSha256Hex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Test-HomelabConstantTimeStringEqual {
    param(
        [AllowNull()]
        [string]$Left,

        [AllowNull()]
        [string]$Right
    )

    if ($null -eq $Left -or $null -eq $Right) {
        return $false
    }

    $leftBytes = [System.Text.Encoding]::UTF8.GetBytes($Left)
    $rightBytes = [System.Text.Encoding]::UTF8.GetBytes($Right)
    $maxLength = [Math]::Max($leftBytes.Length, $rightBytes.Length)
    $diff = $leftBytes.Length -bxor $rightBytes.Length

    for ($index = 0; $index -lt $maxLength; $index++) {
        $leftByte = if ($index -lt $leftBytes.Length) { $leftBytes[$index] } else { 0 }
        $rightByte = if ($index -lt $rightBytes.Length) { $rightBytes[$index] } else { 0 }
        $diff = $diff -bor ($leftByte -bxor $rightByte)
    }

    return $diff -eq 0
}

function Cleanup-HomelabManagerSessions {
    $now = Get-Date
    $remaining = @()

    foreach ($session in (Get-HomelabManagerSessions)) {
        if ($null -eq $session -or -not ($session.PSObject.Properties.Name -contains "token_hash")) {
            continue
        }

        $expiresAt = Get-Date ([string]$session.expires_at)

        if ($expiresAt -gt $now) {
            $remaining += $session
        }
    }

    Save-HomelabManagerSessions -Sessions $remaining
    return $remaining
}

function New-HomelabManagerSession {
    $sessions = Cleanup-HomelabManagerSessions
    $token = New-HomelabManagerSessionToken
    $session = [ordered]@{
        token_hash = Get-HomelabSha256Hex -Value $token
        csrf_token = New-HomelabManagerRandomToken
        created_at = Get-ManagerTimestamp
        expires_at = (Get-Date).AddHours(24).ToString("o")
    }

    $updated = @($sessions) + @($session)
    Save-HomelabManagerSessions -Sessions $updated
    $sessionWithToken = [ordered]@{
        token      = $token
        token_hash = $session.token_hash
        csrf_token = $session.csrf_token
        created_at = $session.created_at
        expires_at = $session.expires_at
    }

    return $sessionWithToken
}

function Remove-HomelabManagerSession {
    param(
        [string]$Token
    )

    $tokenHash = if ([string]::IsNullOrWhiteSpace($Token)) { "" } else { Get-HomelabSha256Hex -Value $Token }
    $sessions = Cleanup-HomelabManagerSessions | Where-Object { [string]$_.token_hash -ne $tokenHash }
    Save-HomelabManagerSessions -Sessions @($sessions)
}

function Get-HomelabManagerSession {
    param(
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $tokenHash = Get-HomelabSha256Hex -Value $Token

    foreach ($session in (Cleanup-HomelabManagerSessions)) {
        if (Test-HomelabConstantTimeStringEqual -Left ([string]$session.token_hash) -Right $tokenHash) {
            return $session
        }
    }

    return $null
}

function Get-HomelabManagerRequestSessionToken {
    param(
        [Parameter(Mandatory = $true)]
        $Request
    )

    $cookie = $Request.Cookies["homelab_manager_session"]

    if ($null -ne $cookie -and -not [string]::IsNullOrWhiteSpace($cookie.Value)) {
        return $cookie.Value
    }

    $authHeader = [string]$Request.Headers["Authorization"]

    if ($authHeader -match "^Bearer\s+(.+)$") {
        return $Matches[1].Trim()
    }

    return $null
}

function Test-HomelabManagerAuthorizedRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Request
    )

    $token = Get-HomelabManagerRequestSessionToken -Request $Request
    return $null -ne (Get-HomelabManagerSession -Token $token)
}

function Get-HomelabManagerAuthorizedSession {
    param(
        [Parameter(Mandatory = $true)]
        $Request
    )

    $token = Get-HomelabManagerRequestSessionToken -Request $Request
    return Get-HomelabManagerSession -Token $token
}

function Test-HomelabManagerCsrfRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Request,

        [Parameter(Mandatory = $true)]
        $Session
    )

    $method = $Request.HttpMethod.ToUpperInvariant()

    if ($method -in @("GET", "HEAD", "OPTIONS")) {
        return $true
    }

    $submittedToken = [string]$Request.Headers["X-CSRF-Token"]

    if ([string]::IsNullOrWhiteSpace($submittedToken)) {
        return $false
    }

    return Test-HomelabConstantTimeStringEqual -Left ([string]$Session.csrf_token) -Right $submittedToken
}

function Read-RequestBodyJson {
    param(
        [Parameter(Mandatory = $true)]
        $Request
    )

    if ($Request.PSObject.Properties.Name -contains "Body") {
        $rawBody = [string]$Request.Body
    }
    else {
        $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)

        try {
            $rawBody = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }

    if ([string]::IsNullOrWhiteSpace($rawBody)) {
        return [pscustomobject]@{}
    }

    return $rawBody | ConvertFrom-Json
}

function Set-ResponseCommonHeaders {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    $Response.Headers["Cache-Control"] = "no-store"
    $Response.Headers["X-Content-Type-Options"] = "nosniff"
}

function Get-HomelabManagerReasonPhrase {
    param(
        [int]$StatusCode
    )

    switch ($StatusCode) {
        200 { return "OK" }
        202 { return "Accepted" }
        204 { return "No Content" }
        400 { return "Bad Request" }
        401 { return "Unauthorized" }
        403 { return "Forbidden" }
        404 { return "Not Found" }
        405 { return "Method Not Allowed" }
        409 { return "Conflict" }
        500 { return "Internal Server Error" }
        default { return "OK" }
    }
}

function Close-HomelabManagerResponse {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    if ($Response.PSObject.Properties.Name -contains "Close" -and $Response.Close -is [scriptblock]) {
        & $Response.Close
        return
    }

    try {
        $Response.Stream.Dispose()
    }
    catch {
    }

    try {
        $Response.Client.Close()
    }
    catch {
    }
}

function Write-HomelabManagerResponse {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        [int]$StatusCode,

        [Parameter(Mandatory = $true)]
        [byte[]]$BodyBytes,

        [Parameter(Mandatory = $true)]
        [string]$ContentType
    )

    if ($Response.PSObject.Properties.Name -contains "OutputStream") {
        $Response.StatusCode = $StatusCode
        $Response.ContentType = $ContentType
        $Response.ContentLength64 = $BodyBytes.Length
        $Response.OutputStream.Write($BodyBytes, 0, $BodyBytes.Length)
        $Response.Close()
        return
    }

    Set-ResponseCommonHeaders -Response $Response
    $headers = [ordered]@{
        "Content-Type" = $ContentType
        "Content-Length" = $BodyBytes.Length
        "Connection" = "close"
    }

    foreach ($headerName in $Response.Headers.Keys) {
        $headers[$headerName] = $Response.Headers[$headerName]
    }

    $headerBuilder = [System.Text.StringBuilder]::new()
    [void]$headerBuilder.Append("HTTP/1.1 $StatusCode $(Get-HomelabManagerReasonPhrase -StatusCode $StatusCode)`r`n")

    foreach ($headerName in $headers.Keys) {
        [void]$headerBuilder.Append("${headerName}: $($headers[$headerName])`r`n")
    }

    [void]$headerBuilder.Append("`r`n")
    $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerBuilder.ToString())
    $Response.Stream.Write($headerBytes, 0, $headerBytes.Length)

    if ($BodyBytes.Length -gt 0) {
        $Response.Stream.Write($BodyBytes, 0, $BodyBytes.Length)
    }

    $Response.Stream.Flush()
    Close-HomelabManagerResponse -Response $Response
}

function Send-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        [int]$StatusCode,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $payload = (Convert-HomelabManagerJsonValue -Value $Value) | ConvertTo-Json -Depth 20
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    Write-HomelabManagerResponse -Response $Response -StatusCode $StatusCode -BodyBytes $bytes -ContentType "application/json; charset=utf-8"
}

function Convert-HomelabManagerJsonValue {
    param(
        $Value
    )

    $psValue = $Value.PSObject
    $baseValue = $Value

    try {
        if ($null -ne $psValue -and $psValue.Properties.Match("BaseObject").Count -gt 0) {
            $baseValue = $psValue.BaseObject
        }
    }
    catch {
        $baseValue = $Value
    }

    if ($null -eq $baseValue) {
        return $null
    }

    if ($baseValue -is [string] -or $baseValue -is [System.ValueType]) {
        return $baseValue
    }

    if ($baseValue -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}

        foreach ($key in $baseValue.Keys) {
            $result[[string]$key] = Convert-HomelabManagerJsonValue -Value $baseValue[$key]
        }

        return [pscustomobject]$result
    }

    if ($baseValue -is [System.Collections.IEnumerable]) {
        $items = New-Object System.Collections.Generic.List[object]

        foreach ($item in $baseValue) {
            $items.Add((Convert-HomelabManagerJsonValue -Value $item))
        }

        return @($items.ToArray())
    }

    $properties = @(
        $psValue.Properties |
            Where-Object {
                $_.MemberType -eq [System.Management.Automation.PSMemberTypes]::NoteProperty
            }
    )

    if ($properties.Count -gt 0) {
        $result = [ordered]@{}

        foreach ($property in $properties) {
            $result[$property.Name] = Convert-HomelabManagerJsonValue -Value $property.Value
        }

        return [pscustomobject]$result
    }

    return $baseValue
}

function Set-HomelabManagerSessionCookie {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        $Request,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$ExpiresAt
    )

    $expires = (Get-Date $ExpiresAt).ToUniversalTime().ToString("R", [System.Globalization.CultureInfo]::InvariantCulture)
    $maxAge = [Math]::Max(0, [int][Math]::Floor(((Get-Date $ExpiresAt) - (Get-Date)).TotalSeconds))
    $secure = if (Test-HomelabManagerHttpsRequest -Request $Request) { "; Secure" } else { "" }
    $cookieValue = "homelab_manager_session=$Token; Path=/; HttpOnly; SameSite=Strict; Expires=$expires; Max-Age=$maxAge$secure"
    $Response.Headers.Add("Set-Cookie", $cookieValue)
}

function Clear-HomelabManagerSessionCookie {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        $Request
    )

    $secure = if (Test-HomelabManagerHttpsRequest -Request $Request) { "; Secure" } else { "" }
    $Response.Headers.Add("Set-Cookie", "homelab_manager_session=; Path=/; HttpOnly; SameSite=Strict; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0$secure")
}

function Test-HomelabManagerHttpsRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Request
    )

    try {
        if ($Request.Url.Scheme -eq "https") {
            return $true
        }
    }
    catch {
    }

    $forwardedProto = [string]$Request.Headers["X-Forwarded-Proto"]

    if ($forwardedProto -match "(^|,\s*)https($|,)") {
        return $true
    }

    $forwarded = [string]$Request.Headers["Forwarded"]

    if ($forwarded -match "(?i)(^|[;,]\s*)proto=https($|[;,])") {
        return $true
    }

    return $false
}

function Get-StaticContentType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    switch ([System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".mjs" { return "application/javascript; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        ".map" { return "application/json; charset=utf-8" }
        ".svg" { return "image/svg+xml" }
        ".ico" { return "image/x-icon" }
        ".png" { return "image/png" }
        ".jpg" { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".webp" { return "image/webp" }
        ".woff" { return "font/woff" }
        ".woff2" { return "font/woff2" }
        ".txt" { return "text/plain; charset=utf-8" }
        ".webmanifest" { return "application/manifest+json; charset=utf-8" }
        default { return "application/octet-stream" }
    }
}

function Resolve-HomelabManagerStaticPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetRoot,

        [Parameter(Mandatory = $true)]
        [string]$RequestPath
    )

    $indexPath = Join-Path $AssetRoot "index.html"

    if ($RequestPath -eq "/" -or [string]::IsNullOrWhiteSpace($RequestPath)) {
        return [pscustomobject]@{
            Path      = $indexPath
            IsSpaPath = $true
        }
    }

    $relativePath = [System.Uri]::UnescapeDataString($RequestPath.TrimStart("/")).Replace("/", "\")
    $candidatePath = [System.IO.Path]::GetFullPath((Join-Path $AssetRoot $relativePath))
    $rootPath = [System.IO.Path]::GetFullPath($AssetRoot).TrimEnd("\")

    if (-not $candidatePath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
        return [pscustomobject]@{
            Path      = $candidatePath
            IsSpaPath = $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($candidatePath))) {
        return $null
    }

    return [pscustomobject]@{
        Path      = $indexPath
        IsSpaPath = $true
    }
}

function Send-StaticFileResponse {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        Send-JsonResponse -Response $Response -StatusCode 404 -Value ([ordered]@{
            error = "not_found"
            message = "Asset not found."
        })
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    Write-HomelabManagerResponse -Response $Response -StatusCode 200 -BodyBytes $bytes -ContentType (Get-StaticContentType -FilePath $FilePath)
}

function Assert-HomelabManagerAuthorizedRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    if (-not (Test-HomelabManagerAuthorizedRequest -Request $Context.Request)) {
        Send-JsonResponse -Response $Context.Response -StatusCode 401 -Value ([ordered]@{
            error = "unauthorized"
            message = "Authentication is required."
        })
        return $false
    }

    return $true
}

function Assert-HomelabManagerCsrfRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $session = Get-HomelabManagerAuthorizedSession -Request $Context.Request

    if ($null -eq $session -or -not (Test-HomelabManagerCsrfRequest -Request $Context.Request -Session $session)) {
        Send-JsonResponse -Response $Context.Response -StatusCode 403 -Value ([ordered]@{
            error = "csrf_failed"
            message = "A valid CSRF token is required."
        })
        return $false
    }

    return $true
}

function Get-HomelabManagerReadOnlyConfig {
    $config = Get-HomelabConfig

    return [ordered]@{
        hostname                = $config.hostname
        openwebui_port          = $config.openwebui_port
        management_port         = $config.management_port
        management_https_port   = $config.management_tailscale_https_port
        management_startup      = $config.management_startup
        runtime_container_backend = $config.runtime_container_backend
        runtime_ollama_backend  = $config.runtime_ollama_backend
        runtime_wsl_distro      = $config.runtime_wsl_distro
        tts_port                = $config.tts_port
    }
}

function Get-HomelabManagerConfigResponse {
    return [ordered]@{
        editable      = Get-EditableHomelabConfig
        read_only     = Get-HomelabManagerReadOnlyConfig
        pending_apply = Get-HomelabManagerPendingApplyState
    }
}

function Get-HomelabManagerSummaryCacheTtlSeconds {
    return 45
}

function Get-HomelabManagerSummaryRefreshLockTtlSeconds {
    return 300
}

function Read-HomelabManagerSummaryCache {
    return Read-JsonFile -Path (Get-ManagerSummaryCachePath) -AllowMissing
}

function Save-HomelabManagerSummaryCache {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$GeneratedAt,

        [Parameter(Mandatory = $true)]
        [int]$DurationMs,

        [string[]]$Errors = @()
    )

    Write-JsonFile -Path (Get-ManagerSummaryCachePath) -Value ([ordered]@{
        generated_at   = $GeneratedAt
        duration_ms    = $DurationMs
        refresh_status = "idle"
        errors         = @($Errors)
        summary        = $Summary
    })
}

function Get-HomelabManagerSummaryRefreshLock {
    $lock = Read-JsonFile -Path (Get-ManagerSummaryRefreshLockPath) -AllowMissing

    if ($null -eq $lock) {
        return $null
    }

    $startedAtText = [string](Get-HomelabObjectPropertyValue -InputObject $lock -Name "started_at" -DefaultValue "")
    $startedAt = [datetime]::MinValue

    if ([datetime]::TryParse($startedAtText, [ref]$startedAt)) {
        $ageSeconds = ((Get-Date) - $startedAt).TotalSeconds

        if ($ageSeconds -le (Get-HomelabManagerSummaryRefreshLockTtlSeconds)) {
            return $lock
        }
    }

    Remove-FileIfPresent -Path (Get-ManagerSummaryRefreshLockPath)
    return $null
}

function Write-HomelabManagerSummaryRefreshLock {
    param(
        [int]$ProcessId = 0
    )

    Write-JsonFile -Path (Get-ManagerSummaryRefreshLockPath) -Value ([ordered]@{
        refresh_status = "running"
        started_at     = Get-ManagerTimestamp
        pid            = if ($ProcessId -gt 0) { $ProcessId } else { $null }
    })
}

function Clear-HomelabManagerSummaryRefreshLock {
    Remove-FileIfPresent -Path (Get-ManagerSummaryRefreshLockPath)
}

function Get-HomelabManagerSummaryCacheAgeSeconds {
    param(
        [object]$Cache
    )

    $generatedAtText = [string](Get-HomelabObjectPropertyValue -InputObject $Cache -Name "generated_at" -DefaultValue "")
    $generatedAt = [datetime]::MinValue

    if (-not [datetime]::TryParse($generatedAtText, [ref]$generatedAt)) {
        return $null
    }

    return [int][math]::Max(0, [math]::Floor(((Get-Date) - $generatedAt).TotalSeconds))
}

function Test-HomelabManagerSummaryCacheFresh {
    param(
        [object]$Cache
    )

    $ageSeconds = Get-HomelabManagerSummaryCacheAgeSeconds -Cache $Cache

    return ($null -ne $ageSeconds -and $ageSeconds -le (Get-HomelabManagerSummaryCacheTtlSeconds))
}

function Get-HomelabManagerSummaryRefreshStatus {
    param(
        [object]$Cache
    )

    if ($null -ne (Get-HomelabManagerSummaryRefreshLock)) {
        return "running"
    }

    if ($null -eq $Cache) {
        return "missing"
    }

    if (Test-HomelabManagerSummaryCacheFresh -Cache $Cache) {
        return "idle"
    }

    return "stale"
}

function Get-HomelabManagerSummaryMeta {
    param(
        [object]$Cache
    )

    return [ordered]@{
        generated_at      = Get-HomelabObjectPropertyValue -InputObject $Cache -Name "generated_at" -DefaultValue $null
        duration_ms       = Get-HomelabObjectPropertyValue -InputObject $Cache -Name "duration_ms" -DefaultValue $null
        cache_age_seconds = Get-HomelabManagerSummaryCacheAgeSeconds -Cache $Cache
        refresh_status    = Get-HomelabManagerSummaryRefreshStatus -Cache $Cache
        errors            = @(Get-HomelabObjectPropertyValue -InputObject $Cache -Name "errors" -DefaultValue @())
    }
}

function Get-HomelabManagerModelsResponse {
    $config = Get-HomelabConfig
    $installedModels = @()

    try {
        if (Test-OllamaReady -Config $config) {
            $installedModels = Get-InstalledOllamaModels -Config $config
        }
    }
    catch {
        $installedModels = @()
    }

    return [ordered]@{
        configured     = @(Get-ConfiguredModels)
        installed      = @($installedModels)
        pending_apply  = Get-HomelabManagerPendingApplyState
        tts_enabled    = [bool]$config.tts_enabled
    }
}

function Add-HomelabManagerSummaryProbeError {
    param(
        [System.Collections.Generic.List[string]]$Errors,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($null -ne $Errors -and -not [string]::IsNullOrWhiteSpace($Message)) {
        [void]$Errors.Add($Message)
    }
}

function Invoke-HomelabManagerCommandSpecProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$CommandSpec,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMs,

        [System.Collections.Generic.List[string]]$Errors
    )

    try {
        $result = Invoke-HomelabCommandSpecWithTimeout -CommandSpec $CommandSpec -Arguments $Arguments -TimeoutMs $TimeoutMs

        if ($result.TimedOut) {
            Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "$Name timed out after $TimeoutMs ms."
            return $null
        }

        return $result
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "$Name failed: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-HomelabManagerNativeProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMs,

        [System.Collections.Generic.List[string]]$Errors
    )

    try {
        $result = Invoke-NativeCommandWithTimeout -FilePath $FilePath -Arguments $Arguments -TimeoutMs $TimeoutMs

        if ($result.TimedOut) {
            Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "$Name timed out after $TimeoutMs ms."
            return $null
        }

        return $result
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "$Name failed: $($_.Exception.Message)"
        return $null
    }
}

function Get-HomelabManagerOllamaVersionProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [System.Collections.Generic.List[string]]$Errors
    )

    $ollamaCommand = Get-OllamaCommandSpec -Config $Config
    $result = Invoke-HomelabManagerCommandSpecProbe -Name "Ollama version" -CommandSpec $ollamaCommand -Arguments $ollamaCommand.VersionArguments -TimeoutMs 5000 -Errors $Errors

    if ($null -eq $result -or $result.ExitCode -ne 0) {
        return $null
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
}

function Test-HomelabManagerOllamaReadyProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [System.Collections.Generic.List[string]]$Errors
    )

    $ollamaCommand = Get-OllamaCommandSpec -Config $Config
    $result = Invoke-HomelabManagerCommandSpecProbe -Name "Ollama list" -CommandSpec $ollamaCommand -Arguments @("list") -TimeoutMs 5000 -Errors $Errors
    return ($null -ne $result -and $result.ExitCode -eq 0)
}

function Get-HomelabManagerInstalledModelsProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [System.Collections.Generic.List[string]]$Errors
    )

    $ollamaCommand = Get-OllamaCommandSpec -Config $Config
    $result = Invoke-HomelabManagerCommandSpecProbe -Name "Installed model list" -CommandSpec $ollamaCommand -Arguments @("list") -TimeoutMs 7000 -Errors $Errors

    if ($null -eq $result -or $result.ExitCode -ne 0) {
        return @()
    }

    return ($result.StdOut -split "\r?\n") |
        Select-Object -Skip 1 |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { $_ } |
        ForEach-Object { ($_ -split '\s+')[0] }
}

function Test-HomelabManagerDockerReadyProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [System.Collections.Generic.List[string]]$Errors
    )

    $dockerCommand = Get-DockerCommandSpec -Config $Config
    $result = Invoke-HomelabManagerCommandSpecProbe -Name "Docker daemon" -CommandSpec $dockerCommand -Arguments @("info", "--format", "{{.ServerVersion}}") -TimeoutMs 5000 -Errors $Errors
    return ($null -ne $result -and $result.ExitCode -eq 0)
}

function Get-HomelabManagerContainerHealthProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [System.Collections.Generic.List[string]]$Errors
    )

    $dockerCommand = Get-DockerCommandSpec -Config $Config
    $result = Invoke-HomelabManagerCommandSpecProbe -Name "Container health $ContainerName" -CommandSpec $dockerCommand -Arguments @(
        "inspect",
        "--format",
        "{{if .State.Running}}{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}{{else}}stopped{{end}}",
        $ContainerName
    ) -TimeoutMs 5000 -Errors $Errors

    if ($null -eq $result) {
        return "unknown"
    }

    if ($result.ExitCode -ne 0) {
        return "missing"
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
}

function Invoke-HomelabManagerTailscaleJsonProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string[]]$Arguments = @(),

        [System.Collections.Generic.List[string]]$Errors
    )

    $result = Invoke-HomelabManagerNativeProbe -Name $Name -FilePath (Get-TailscalePath) -Arguments $Arguments -TimeoutMs 5000 -Errors $Errors

    if ($null -eq $result -or $result.ExitCode -ne 0) {
        return $null
    }

    try {
        return ConvertFrom-JsonOrThrow -InputText $result.StdOut -CommandName $Name
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "$Name returned invalid JSON: $($_.Exception.Message)"
        return $null
    }
}

function Get-HomelabManagerTailscaleNodeInfoProbe {
    param(
        [System.Collections.Generic.List[string]]$Errors
    )

    $status = Invoke-HomelabManagerTailscaleJsonProbe -Name "tailscale status --json" -Arguments @("status", "--json") -Errors $Errors

    if ($null -eq $status -or -not $status.Self) {
        return $null
    }

    $dnsName = Get-NormalizedTailscaleDnsName -DnsName ([string]$status.Self.DNSName)

    if ([string]::IsNullOrWhiteSpace($dnsName)) {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Tailscale did not report a node DNS name."
        return $null
    }

    $certDomains = @()
    $rawCertDomains = Get-HomelabObjectPropertyValue -InputObject $status -Name "CertDomains" -DefaultValue $null

    if ($null -ne $rawCertDomains) {
        $certDomains = @($rawCertDomains | ForEach-Object { Get-NormalizedTailscaleDnsName -DnsName ([string]$_) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return [pscustomobject]@{
        Status                   = $status
        DnsName                  = $dnsName
        HttpsUrl                 = "https://$dnsName"
        MagicDnsEnabled          = [bool]($status.CurrentTailnet -and $status.CurrentTailnet.MagicDNSEnabled)
        HttpsCertificatesEnabled = ($certDomains.Count -gt 0)
        CertDomains              = $certDomains
    }
}

function Get-HomelabManagerTailscaleServeProxyStateProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$NodeInfo,

        [Parameter(Mandatory = $true)]
        [int]$HttpsPort,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedProxyTarget,

        [System.Collections.Generic.List[string]]$Errors
    )

    $statusJson = Invoke-HomelabManagerTailscaleJsonProbe -Name "tailscale serve status --json" -Arguments @("serve", "status", "--json") -Errors $Errors
    $configJson = Invoke-HomelabManagerTailscaleJsonProbe -Name "tailscale serve get-config --all -" -Arguments @("serve", "get-config", "--all", "-") -Errors $Errors

    if ($null -eq $statusJson -or $null -eq $configJson) {
        return $null
    }

    $hasHttpsPort = (
        (Test-TailscaleServeObjectHasHttpsPort -InputObject $statusJson -HttpsPort $HttpsPort) -or
        (Test-TailscaleServeObjectHasHttpsPort -InputObject $configJson -HttpsPort $HttpsPort)
    )
    $hasExpectedTarget = (
        (Test-TailscaleServeObjectHasExpectedWebProxy -InputObject $statusJson -DnsName $NodeInfo.DnsName -HttpsPort $HttpsPort -ExpectedProxyTarget $ExpectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedWebProxy -InputObject $configJson -DnsName $NodeInfo.DnsName -HttpsPort $HttpsPort -ExpectedProxyTarget $ExpectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedEndpoint -InputObject $statusJson -HttpsPort $HttpsPort -ExpectedProxyTarget $ExpectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedEndpoint -InputObject $configJson -HttpsPort $HttpsPort -ExpectedProxyTarget $ExpectedProxyTarget)
    )

    return [pscustomobject]@{
        IsConfiguredExpected = ($hasHttpsPort -and $hasExpectedTarget)
        ExpectedProxyTarget  = $ExpectedProxyTarget
        HttpsPort            = $HttpsPort
    }
}

function Get-HomelabManagerFullSummarySnapshot {
    param(
        [System.Collections.Generic.List[string]]$Errors
    )

    $config = Get-HomelabConfig
    $ollamaReady = $false
    $ollamaVersion = $null
    $dockerReady = $false
    $openWebUiHealth = "unknown"
    $ttsHealth = if ($config.tts_enabled) { "unknown" } else { "disabled" }
    $runtimePatchState = "unknown"
    $whisperCacheState = $null
    $installedModels = @()

    try {
        $ollamaVersion = Get-HomelabManagerOllamaVersionProbe -Config $config -Errors $Errors
        $ollamaReady = Test-HomelabManagerOllamaReadyProbe -Config $config -Errors $Errors

        if ($ollamaReady) {
            $installedModels = Get-HomelabManagerInstalledModelsProbe -Config $config -Errors $Errors
        }
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Ollama probe failed: $($_.Exception.Message)"
        $ollamaReady = $false
    }

    try {
        $dockerReady = Test-HomelabManagerDockerReadyProbe -Config $config -Errors $Errors
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Docker probe failed: $($_.Exception.Message)"
        $dockerReady = $false
    }

    if ($dockerReady) {
        $openWebUiHealth = Get-HomelabManagerContainerHealthProbe -Config $config -ContainerName $config.openwebui_container_name -Errors $Errors

        if ($config.tts_enabled) {
            $ttsHealth = Get-HomelabManagerContainerHealthProbe -Config $config -ContainerName $config.tts_container_name -Errors $Errors
        }

        if ($openWebUiHealth -in @("healthy", "running")) {
            try {
                $runtimePatchState = Get-OpenWebUiRuntimePatchState -Config $config
            }
            catch {
                Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Open WebUI runtime patch probe failed: $($_.Exception.Message)"
                $runtimePatchState = "unknown"
            }

            try {
                $whisperCacheState = Get-OpenWebUiWhisperCacheState -Config $config
            }
            catch {
                Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Open WebUI Whisper cache probe failed: $($_.Exception.Message)"
                $whisperCacheState = $null
            }
        }
    }
    else {
        $openWebUiHealth = "daemon-unavailable"

        if ($config.tts_enabled) {
            $ttsHealth = "daemon-unavailable"
        }
    }

    $openWebUiUrl = "http://127.0.0.1:$($config.openwebui_port)"
    $managementUrl = Get-HomelabManagerLocalUrl -Config $config
    $ttsUrl = "http://127.0.0.1:$($config.tts_port)"
    $openWebUiHttp = Test-HttpEndpoint -Url $openWebUiUrl -TimeoutSeconds 2
    $managementHttp = [pscustomobject]@{ Ok = $true; StatusCode = 200 }
    $ttsHttp = if ($config.tts_enabled) {
        Test-HttpEndpoint -Url "$ttsUrl/docs" -TimeoutSeconds 2
    }
    else {
        $null
    }

    $tailscaleNodeInfo = $null
    $webUiServeState = $null
    $managementServeState = $null
    $tailscaleError = $null

    try {
        $tailscaleNodeInfo = Get-HomelabManagerTailscaleNodeInfoProbe -Errors $Errors

        if ($null -ne $tailscaleNodeInfo) {
            $webUiServeState = Get-HomelabManagerTailscaleServeProxyStateProbe -Config $config -NodeInfo $tailscaleNodeInfo -HttpsPort 443 -ExpectedProxyTarget "http://127.0.0.1:$($config.openwebui_port)" -Errors $Errors
            $managementServeState = Get-HomelabManagerTailscaleServeProxyStateProbe -Config $config -NodeInfo $tailscaleNodeInfo -HttpsPort $config.management_tailscale_https_port -ExpectedProxyTarget "http://127.0.0.1:$($config.management_port)" -Errors $Errors
        }
    }
    catch {
        $tailscaleError = $_.Exception.Message
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Tailscale probe failed: $tailscaleError"
    }

    $lockInfo = Get-HomelabManagerLockInfo

    return [ordered]@{
        manager = [ordered]@{
            running                   = ($null -ne $lockInfo)
            pid                       = if ($null -ne $lockInfo) { [int]$lockInfo.pid } else { $null }
            started_at                = if ($null -ne $lockInfo) { [string]$lockInfo.started_at } else { $null }
            local_url                 = $managementUrl
            local_reachable           = [bool]$managementHttp.Ok
            scheduled_task_registered = Test-HomelabManagerTaskRegistered
            management_https_port     = $config.management_tailscale_https_port
        }
        stack = [ordered]@{
            ollama = [ordered]@{
                ready   = $ollamaReady
                version = $ollamaVersion
            }
            docker = [ordered]@{
                ready = $dockerReady
            }
            open_webui = [ordered]@{
                health             = $openWebUiHealth
                local_url          = $openWebUiUrl
                local_reachable    = [bool]$openWebUiHttp.Ok
                runtime_patch      = $runtimePatchState
                whisper_cache      = $whisperCacheState
            }
            tts = [ordered]@{
                enabled         = [bool]$config.tts_enabled
                health          = $ttsHealth
                local_url       = $ttsUrl
                local_reachable = if ($null -ne $ttsHttp) { [bool]$ttsHttp.Ok } else { $false }
            }
        }
        models = [ordered]@{
            configured = @(Get-ConfiguredModels)
            installed  = @($installedModels)
        }
        config = [ordered]@{
            editable  = Get-EditableHomelabConfig
            read_only = Get-HomelabManagerReadOnlyConfig
        }
        tailscale = [ordered]@{
            available             = ($null -ne $tailscaleNodeInfo)
            error                 = $tailscaleError
            https_url             = if ($null -ne $tailscaleNodeInfo) { $tailscaleNodeInfo.HttpsUrl } else { $null }
            management_remote_url = if ($null -ne $tailscaleNodeInfo) { Get-HomelabManagerRemoteUrl -Config $config -NodeInfo $tailscaleNodeInfo } else { $null }
            magic_dns_enabled     = if ($null -ne $tailscaleNodeInfo) { [bool]$tailscaleNodeInfo.MagicDnsEnabled } else { $false }
            certs_enabled         = if ($null -ne $tailscaleNodeInfo) { [bool]$tailscaleNodeInfo.HttpsCertificatesEnabled } else { $false }
            open_webui            = if ($null -ne $webUiServeState) {
                [ordered]@{
                    configured_expected = [bool]$webUiServeState.IsConfiguredExpected
                    expected_target     = [string]$webUiServeState.ExpectedProxyTarget
                }
            } else { $null }
            management            = if ($null -ne $managementServeState) {
                [ordered]@{
                    configured_expected = [bool]$managementServeState.IsConfiguredExpected
                    expected_target     = [string]$managementServeState.ExpectedProxyTarget
                    https_port          = [int]$managementServeState.HttpsPort
                }
            } else { $null }
        }
        jobs = Get-HomelabManagerFastJobsSnapshot
        meta = $null
    }
}

function New-HomelabManagerDefaultSummary {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $managementUrl = Get-HomelabManagerLocalUrl -Config $Config
    $openWebUiUrl = "http://127.0.0.1:$($Config.openwebui_port)"
    $ttsUrl = "http://127.0.0.1:$($Config.tts_port)"

    return [ordered]@{
        manager = [ordered]@{
            running                   = $false
            pid                       = $null
            started_at                = $null
            local_url                 = $managementUrl
            local_reachable           = $true
            scheduled_task_registered = $false
            management_https_port     = $Config.management_tailscale_https_port
        }
        stack = [ordered]@{
            ollama = [ordered]@{
                ready   = $false
                version = $null
            }
            docker = [ordered]@{
                ready = $false
            }
            open_webui = [ordered]@{
                health          = "unknown"
                local_url       = $openWebUiUrl
                local_reachable = $false
                runtime_patch   = "unknown"
                whisper_cache   = $null
            }
            tts = [ordered]@{
                enabled         = [bool]$Config.tts_enabled
                health          = if ($Config.tts_enabled) { "unknown" } else { "disabled" }
                local_url       = $ttsUrl
                local_reachable = $false
            }
        }
        models = [ordered]@{
            configured = @(Get-ConfiguredModels)
            installed  = @()
        }
        config = [ordered]@{
            editable  = Get-EditableHomelabConfig
            read_only = Get-HomelabManagerReadOnlyConfig
        }
        tailscale = [ordered]@{
            available             = $false
            error                 = $null
            https_url             = $null
            management_remote_url = $null
            magic_dns_enabled     = $false
            certs_enabled         = $false
            open_webui            = $null
            management            = $null
        }
        jobs = Get-HomelabManagerFastJobsSnapshot
        meta = $null
    }
}

function Get-HomelabManagerFastSummary {
    param(
        [object]$Cache
    )

    $config = Get-HomelabConfig
    $cachedSummary = Get-HomelabObjectPropertyValue -InputObject $Cache -Name "summary" -DefaultValue $null
    $summary = if ($null -ne $cachedSummary) {
        $cachedSummary
    }
    else {
        New-HomelabManagerDefaultSummary -Config $config
    }

    $lockInfo = Get-HomelabManagerLockInfo
    $manager = Get-HomelabObjectPropertyValue -InputObject $summary -Name "manager" -DefaultValue $null
    $stack = Get-HomelabObjectPropertyValue -InputObject $summary -Name "stack" -DefaultValue $null
    $tts = if ($null -ne $stack) { Get-HomelabObjectPropertyValue -InputObject $stack -Name "tts" -DefaultValue $null } else { $null }
    $models = Get-HomelabObjectPropertyValue -InputObject $summary -Name "models" -DefaultValue $null
    $configSection = Get-HomelabObjectPropertyValue -InputObject $summary -Name "config" -DefaultValue $null

    if ($null -ne $manager) {
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "running" -Value ($null -ne $lockInfo)
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "pid" -Value $(if ($null -ne $lockInfo) { [int]$lockInfo.pid } else { $null })
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "started_at" -Value $(if ($null -ne $lockInfo) { [string]$lockInfo.started_at } else { $null })
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "local_url" -Value (Get-HomelabManagerLocalUrl -Config $config)
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "local_reachable" -Value $true
        Set-HomelabObjectPropertyValue -InputObject $manager -Name "management_https_port" -Value $config.management_tailscale_https_port
    }

    if ($null -ne $tts) {
        Set-HomelabObjectPropertyValue -InputObject $tts -Name "enabled" -Value ([bool]$config.tts_enabled)
        Set-HomelabObjectPropertyValue -InputObject $tts -Name "local_url" -Value "http://127.0.0.1:$($config.tts_port)"
    }

    if ($null -ne $models) {
        Set-HomelabObjectPropertyValue -InputObject $models -Name "configured" -Value @(Get-ConfiguredModels)
    }

    if ($null -ne $configSection) {
        Set-HomelabObjectPropertyValue -InputObject $configSection -Name "editable" -Value (Get-EditableHomelabConfig)
        Set-HomelabObjectPropertyValue -InputObject $configSection -Name "read_only" -Value (Get-HomelabManagerReadOnlyConfig)
    }

    Set-HomelabObjectPropertyValue -InputObject $summary -Name "jobs" -Value (Get-HomelabManagerFastJobsSnapshot)
    Set-HomelabObjectPropertyValue -InputObject $summary -Name "meta" -Value (Get-HomelabManagerSummaryMeta -Cache $Cache)

    return $summary
}

function Start-HomelabManagerSummaryRefresh {
    param(
        [switch]$Force
    )

    $cache = Read-HomelabManagerSummaryCache

    if (-not $Force -and (Test-HomelabManagerSummaryCacheFresh -Cache $cache)) {
        return $false
    }

    if ($null -ne (Get-HomelabManagerSummaryRefreshLock)) {
        return $false
    }

    Write-HomelabManagerSummaryRefreshLock
    $refreshScript = Join-Path $script:HomelabRoot "scripts\manager-summary-refresh.ps1"

    try {
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $refreshScript
        ) -WindowStyle Hidden -PassThru
        Write-HomelabManagerSummaryRefreshLock -ProcessId $process.Id
        return $true
    }
    catch {
        Clear-HomelabManagerSummaryRefreshLock
        throw
    }
}

function Invoke-HomelabManagerSummaryRefresh {
    Write-HomelabManagerSummaryRefreshLock -ProcessId $PID
    $startedAt = Get-Date
    $generatedAt = Get-ManagerTimestamp
    $errors = [System.Collections.Generic.List[string]]::new()

    try {
        $snapshot = Get-HomelabManagerFullSummarySnapshot -Errors $errors
        $durationMs = [int][math]::Round(((Get-Date) - $startedAt).TotalMilliseconds)
        Save-HomelabManagerSummaryCache -Summary $snapshot -GeneratedAt $generatedAt -DurationMs $durationMs -Errors @($errors)
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $errors -Message "Summary refresh failed: $($_.Exception.Message)"
        $cache = Read-HomelabManagerSummaryCache
        $fallback = Get-HomelabObjectPropertyValue -InputObject $cache -Name "summary" -DefaultValue $null

        if ($null -eq $fallback) {
            $fallback = New-HomelabManagerDefaultSummary -Config (Get-HomelabConfig)
        }

        $durationMs = [int][math]::Round(((Get-Date) - $startedAt).TotalMilliseconds)
        Save-HomelabManagerSummaryCache -Summary $fallback -GeneratedAt $generatedAt -DurationMs $durationMs -Errors @($errors)
    }
    finally {
        Clear-HomelabManagerSummaryRefreshLock
    }
}

function Get-HomelabManagerSummary {
    $cache = Read-HomelabManagerSummaryCache

    if (-not (Test-HomelabManagerSummaryCacheFresh -Cache $cache)) {
        try {
            [void](Start-HomelabManagerSummaryRefresh)
        }
        catch {
        }
    }

    $cache = Read-HomelabManagerSummaryCache
    return Get-HomelabManagerFastSummary -Cache $cache
}

function Request-HomelabManagerSummaryRefresh {
    try {
        [void](Start-HomelabManagerSummaryRefresh -Force)
    }
    catch {
    }

    return Get-HomelabManagerFastSummary -Cache (Read-HomelabManagerSummaryCache)
}

function Send-HomelabManagerJobStream {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    if ($Response.PSObject.Properties.Name -contains "OutputStream") {
        Set-ResponseCommonHeaders -Response $Response
        $Response.StatusCode = 200
        $Response.ContentType = "text/event-stream"
        $Response.Headers["Connection"] = "keep-alive"
        $stream = $Response.OutputStream
    }
    else {
        Set-ResponseCommonHeaders -Response $Response
        $Response.Headers["Content-Type"] = "text/event-stream; charset=utf-8"
        $Response.Headers["Connection"] = "keep-alive"
        $headerBuilder = [System.Text.StringBuilder]::new()
        [void]$headerBuilder.Append("HTTP/1.1 200 OK`r`n")

        foreach ($headerName in $Response.Headers.Keys) {
            [void]$headerBuilder.Append("${headerName}: $($Response.Headers[$headerName])`r`n")
        }

        [void]$headerBuilder.Append("`r`n")
        $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerBuilder.ToString())
        $Response.Stream.Write($headerBytes, 0, $headerBytes.Length)
        $Response.Stream.Flush()
        $stream = $Response.Stream
    }

    $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
    $lastPayload = ""
    $heartbeatIntervalSeconds = 10
    $streamLifetimeMinutes = 5

    try {
        $startedAt = Get-Date
        $lastHeartbeatAt = $startedAt

        while (((Get-Date) - $startedAt).TotalMinutes -lt $streamLifetimeMinutes) {
            $payload = (Convert-HomelabManagerJsonValue -Value (Get-HomelabManagerFastJobsSnapshot) | ConvertTo-Json -Depth 20 -Compress)

            if ($payload -ne $lastPayload) {
                $writer.Write("event: update`n")
                $writer.Write("data: $payload`n`n")
                $writer.Flush()
                $lastPayload = $payload
                $lastHeartbeatAt = Get-Date
            }
            elseif (((Get-Date) - $lastHeartbeatAt).TotalSeconds -ge $heartbeatIntervalSeconds) {
                $writer.Write(": keepalive`n`n")
                $writer.Flush()
                $lastHeartbeatAt = Get-Date
            }

            Start-Sleep -Milliseconds 1000
        }
    }
    catch {
    }
    finally {
        try {
            $writer.Dispose()
        }
        catch {
        }

        try {
            Close-HomelabManagerResponse -Response $Response
        }
        catch {
        }
    }
}

function Handle-HomelabManagerApiRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $request = $Context.Request
    $response = $Context.Response
    $method = $request.HttpMethod.ToUpperInvariant()

    if ($Path -eq "/api/auth/login" -and $method -eq "POST") {
        $config = Get-HomelabConfig
        Assert-ManagementAdminSecretConfigured -Config $config
        $body = Read-RequestBodyJson -Request $request
        $submittedSecretHash = Get-HomelabSha256Hex -Value ([string]$body.secret)
        $expectedSecretHash = Get-HomelabSha256Hex -Value ([string]$config.management_admin_secret)

        if (-not (Test-HomelabConstantTimeStringEqual -Left $submittedSecretHash -Right $expectedSecretHash)) {
            Send-JsonResponse -Response $response -StatusCode 401 -Value ([ordered]@{
                error = "invalid_credentials"
                message = "The admin secret is incorrect."
            })
            return
        }

        $session = New-HomelabManagerSession
        Set-HomelabManagerSessionCookie -Response $response -Request $request -Token ([string]$session.token) -ExpiresAt ([string]$session.expires_at)
        Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
            ok         = $true
            expires_at = $session.expires_at
            csrf_token = $session.csrf_token
        })
        return
    }

    if (-not (Assert-HomelabManagerAuthorizedRequest -Context $Context)) {
        return
    }

    if ($method -notin @("GET", "HEAD", "OPTIONS") -and -not (Assert-HomelabManagerCsrfRequest -Context $Context)) {
        return
    }

    switch ("$method $Path") {
        "GET /api/auth/session" {
            $session = Get-HomelabManagerAuthorizedSession -Request $request
            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                ok         = $true
                expires_at = $session.expires_at
                csrf_token = $session.csrf_token
            })
            return
        }
        "POST /api/auth/logout" {
            $token = Get-HomelabManagerRequestSessionToken -Request $request

            if (-not [string]::IsNullOrWhiteSpace($token)) {
                Remove-HomelabManagerSession -Token $token
            }

            Clear-HomelabManagerSessionCookie -Response $response -Request $request
            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                ok = $true
            })
            return
        }
        "GET /api/summary" {
            Send-JsonResponse -Response $response -StatusCode 200 -Value (Get-HomelabManagerSummary)
            return
        }
        "POST /api/summary/refresh" {
            Send-JsonResponse -Response $response -StatusCode 202 -Value (Request-HomelabManagerSummaryRefresh)
            return
        }
        "GET /api/config" {
            Send-JsonResponse -Response $response -StatusCode 200 -Value (Get-HomelabManagerConfigResponse)
            return
        }
        "PUT /api/config" {
            $before = Get-EditableHomelabConfig | ConvertTo-Json -Depth 20 -Compress
            $body = Read-RequestBodyJson -Request $request
            $savedConfig = Save-EditableHomelabConfig -EditableConfig $body
            $after = $savedConfig | ConvertTo-Json -Depth 20 -Compress
            $pendingApply = if ($before -ne $after) {
                Set-HomelabManagerPendingApplyState -ConfigChanged $true -ModelsChanged $false
            }
            else {
                Get-HomelabManagerPendingApplyState
            }

            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                editable      = $savedConfig
                read_only     = Get-HomelabManagerReadOnlyConfig
                pending_apply = $pendingApply
            })
            return
        }
        "GET /api/models" {
            Send-JsonResponse -Response $response -StatusCode 200 -Value (Get-HomelabManagerModelsResponse)
            return
        }
        "PUT /api/models" {
            $body = Read-RequestBodyJson -Request $request

            if ($null -eq $body.models) {
                throw "The request body must contain a 'models' array."
            }

            $config = Get-HomelabConfig
            $beforeModels = @(Get-ConfiguredModels)
            $diff = Get-OllamaModelListDiff -CurrentModels $beforeModels -DesiredModels @($body.models)
            $uninstallRemoved = [bool]$body.uninstall_removed
            $savedModels = Save-ConfiguredModels -Models @($body.models)
            $modelsChanged = (@($diff.added).Count -gt 0 -or @($diff.removed).Count -gt 0)

            $uninstallResult = [ordered]@{
                requested = $uninstallRemoved
                removed   = @()
                skipped   = @()
                error     = $null
            }

            if ($uninstallRemoved -and @($diff.removed).Count -gt 0) {
                try {
                    $removal = Remove-OllamaModels -Config $config -Models @($diff.removed)
                    $uninstallResult.removed = @($removal.removed)
                    $uninstallResult.skipped = @($removal.skipped)
                }
                catch {
                    $uninstallResult.error = $_.Exception.Message
                }
            }

            $pendingApply = if ($modelsChanged) {
                Set-HomelabManagerPendingApplyState -ConfigChanged $false -ModelsChanged $true -AddedModels @($diff.added) -RemovedModels @($diff.removed)
            }
            else {
                Get-HomelabManagerPendingApplyState
            }

            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                configured        = @($savedModels)
                installed         = @((Get-HomelabManagerModelsResponse).installed)
                pending_apply     = $pendingApply
                added_models      = @($diff.added)
                removed_models    = @($diff.removed)
                uninstall_removed = $uninstallRemoved
                uninstall_result  = $uninstallResult
            })
            return
        }
        "GET /api/jobs/current" {
            $snapshot = Get-HomelabManagerJobsSnapshot
            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                current       = $snapshot.current
                latest        = $snapshot.latest
                pending_apply = $snapshot.pending_apply
            })
            return
        }
        "GET /api/jobs/history" {
            $snapshot = Get-HomelabManagerJobsSnapshot
            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                history = $snapshot.history
            })
            return
        }
        "GET /api/jobs/stream" {
            Send-HomelabManagerJobStream -Response $response
            return
        }
    }

    if ($method -eq "POST" -and $Path.StartsWith("/api/actions/")) {
        $actionName = $Path.Substring("/api/actions/".Length)
        $job = Start-HomelabManagerActionJob -ActionName $actionName
        Send-JsonResponse -Response $response -StatusCode 202 -Value ([ordered]@{
            accepted = $true
            job      = $job
        })
        return
    }

    Send-JsonResponse -Response $response -StatusCode 404 -Value ([ordered]@{
        error = "not_found"
        message = "The requested API endpoint does not exist."
    })
}

function Handle-HomelabManagerRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $request = $Context.Request
    $path = $request.Url.AbsolutePath

    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = "/"
    }

    if ($path.StartsWith("/api/")) {
        Handle-HomelabManagerApiRequest -Context $Context -Path $path
        return
    }

    $assetRoot = Join-Path $script:HomelabRoot "scripts\manager-ui\dist"
    $resolvedAsset = Resolve-HomelabManagerStaticPath -AssetRoot $assetRoot -RequestPath $path

    if ($null -eq $resolvedAsset) {
        Send-JsonResponse -Response $Context.Response -StatusCode 404 -Value ([ordered]@{
            error = "not_found"
            message = "Asset not found."
        })
        return
    }

    Send-StaticFileResponse -Response $Context.Response -FilePath ([string]$resolvedAsset.Path)
    return
}
