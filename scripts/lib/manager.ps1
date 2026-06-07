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

    $rootPath = [System.IO.Path]::GetFullPath($script:HomelabRoot).TrimEnd('\')
    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if ($fullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($rootPath.Length).TrimStart('\')
    }

    return $fullPath
}

function Get-ManagerTimestamp {
    return (Get-Date).ToString("o")
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$AllowMissing
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($AllowMissing) {
            return $null
        }

        throw "JSON file not found: $Path"
    }

    $rawText = Get-Content -Raw -LiteralPath $Path

    if ([string]::IsNullOrWhiteSpace($rawText)) {
        return $null
    }

    return $rawText | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $directory = Split-Path -Parent $Path

    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $json = $Value | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($Path, ($json + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
}

function Remove-FileIfPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

function Test-ProcessAlive {
    param(
        [int]$Id
    )

    if ($Id -le 0) {
        return $false
    }

    try {
        $null = Get-Process -Id $Id -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
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

function Get-HomelabManagerTaskQuery {
    foreach ($taskName in @(Get-HomelabManagerTaskNameCandidates)) {
        $result = Invoke-NativeCommand -FilePath "schtasks.exe" -Arguments @("/Query", "/TN", $taskName, "/FO", "LIST")

        if ($result.ExitCode -eq 0) {
            return [pscustomobject]@{
                Exists   = $true
                Raw      = (($result.StdOut + [Environment]::NewLine + $result.StdErr).Trim())
                ExitCode = $result.ExitCode
            }
        }
    }

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
                    return [pscustomobject]@{
                        Exists   = $true
                        Raw      = "Task Scheduler COM query matched $normalizedTaskName."
                        ExitCode = 0
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
        Exists   = $false
        Raw      = "Task query failed for all candidates: $([string]::Join(', ', @(Get-HomelabManagerTaskNameCandidates)))."
        ExitCode = 1
    }
}

function Test-HomelabManagerTaskRegistered {
    return (Get-HomelabManagerTaskQuery).Exists
}

function Register-HomelabManagerScheduledTask {
    Assert-TailscaleAdminAccess

    $startScriptPath = Join-Path $script:HomelabRoot "scripts\manager-start.ps1"
    $powershellPath = Get-HomelabManagerExecutablePath
    $taskCommand = '"' + $powershellPath + '" -NoProfile -ExecutionPolicy Bypass -File "' + $startScriptPath + '"'
    $taskName = Get-HomelabManagerTaskName

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
        "/TR",
        $taskCommand,
        "/F"
    )

    if ($result.ExitCode -ne 0) {
        throw (($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim())
    }
}

function Unregister-HomelabManagerScheduledTask {
    $taskName = Get-HomelabManagerTaskName
    $result = Invoke-NativeCommand -FilePath "schtasks.exe" -Arguments @("/Delete", "/TN", $taskName, "/F")

    if ($result.ExitCode -ne 0 -and $result.StdOut -notmatch "cannot find the file specified") {
        throw (($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim())
    }
}

function Start-HomelabManagerScheduledTask {
    $taskName = Get-HomelabManagerTaskName
    $result = Invoke-NativeCommand -FilePath "schtasks.exe" -Arguments @("/Run", "/TN", $taskName)

    if ($result.ExitCode -ne 0) {
        throw (($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim())
    }
}

function Get-HomelabManagerCurrentJob {
    return Read-JsonFile -Path (Get-ManagerCurrentJobPath) -AllowMissing
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

    return @($history)
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
        [object]$Job
    )

    if ($null -eq $Job) {
        return $null
    }

    $tail = Get-HomelabManagerJobLogTail -LogPath ([string]$Job.log_path)

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
        log_tail          = @($tail)
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
    $currentJob = Add-HomelabManagerJobTail -Job (Get-HomelabManagerCurrentJob)
    $lastJob = Add-HomelabManagerJobTail -Job (Get-HomelabManagerLastJob)
    $history = @()

    foreach ($job in (Get-HomelabManagerJobHistory)) {
        $history += (Add-HomelabManagerJobTail -Job $job)
    }

    return [ordered]@{
        current       = $currentJob
        latest        = $lastJob
        history       = @($history)
        pending_apply = Get-HomelabManagerPendingApplyState
    }
}

function New-HomelabManagerSessionToken {
    return ([guid]::NewGuid().ToString("n") + [guid]::NewGuid().ToString("n"))
}

function Cleanup-HomelabManagerSessions {
    $now = Get-Date
    $remaining = @()

    foreach ($session in (Get-HomelabManagerSessions)) {
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
    $session = [ordered]@{
        token      = New-HomelabManagerSessionToken
        created_at = Get-ManagerTimestamp
        expires_at = (Get-Date).AddHours(24).ToString("o")
    }

    $updated = @($sessions) + @($session)
    Save-HomelabManagerSessions -Sessions $updated
    return $session
}

function Remove-HomelabManagerSession {
    param(
        [string]$Token
    )

    $sessions = Cleanup-HomelabManagerSessions | Where-Object { [string]$_.token -ne $Token }
    Save-HomelabManagerSessions -Sessions $sessions
}

function Get-HomelabManagerSession {
    param(
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    foreach ($session in (Cleanup-HomelabManagerSessions)) {
        if ([string]$session.token -eq $Token) {
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

function Send-TextResponse {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        [int]$StatusCode,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [string]$ContentType = "text/plain; charset=utf-8"
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    Write-HomelabManagerResponse -Response $Response -StatusCode $StatusCode -BodyBytes $bytes -ContentType $ContentType
}

function Send-NoContentResponse {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        [int]$StatusCode
    )

    Write-HomelabManagerResponse -Response $Response -StatusCode $StatusCode -BodyBytes @() -ContentType "text/plain; charset=utf-8"
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
        [string]$Token
    )

    $cookieValue = "homelab_manager_session=$Token; Path=/; HttpOnly; SameSite=Strict"
    $Response.Headers.Add("Set-Cookie", $cookieValue)
}

function Clear-HomelabManagerSessionCookie {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    $Response.Headers.Add("Set-Cookie", "homelab_manager_session=; Path=/; HttpOnly; SameSite=Strict; Expires=Thu, 01 Jan 1970 00:00:00 GMT")
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
        ".json" { return "application/json; charset=utf-8" }
        default { return "application/octet-stream" }
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

function Get-HomelabManagerReadOnlyConfig {
    $config = Get-HomelabConfig

    return [ordered]@{
        hostname                = $config.hostname
        openwebui_port          = $config.openwebui_port
        management_port         = $config.management_port
        management_https_port   = $config.management_tailscale_https_port
        management_startup      = $config.management_startup
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

function Get-HomelabManagerModelsResponse {
    $config = Get-HomelabConfig
    $ollamaPath = $null
    $installedModels = @()

    try {
        $ollamaPath = Get-OllamaPath

        if (Test-OllamaReady -OllamaPath $ollamaPath) {
            $installedModels = Get-InstalledOllamaModels -OllamaPath $ollamaPath
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

function Get-HomelabManagerSummary {
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
        $ollamaPath = Get-OllamaPath
        $ollamaVersion = Get-CommandVersion -CommandPath $ollamaPath
        $ollamaReady = Test-OllamaReady -OllamaPath $ollamaPath

        if ($ollamaReady) {
            $installedModels = Get-InstalledOllamaModels -OllamaPath $ollamaPath
        }
    }
    catch {
        $ollamaReady = $false
    }

    try {
        $dockerReady = Test-DockerDaemonReady
    }
    catch {
        $dockerReady = $false
    }

    if ($dockerReady) {
        $openWebUiHealth = Get-OpenWebUiHealth -Config $config

        if ($config.tts_enabled) {
            $ttsHealth = Get-TtsHealth -Config $config
        }

        if ($openWebUiHealth -in @("healthy", "running")) {
            $runtimePatchState = Get-OpenWebUiRuntimePatchState -Config $config
            $whisperCacheState = Get-OpenWebUiWhisperCacheState -Config $config
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
    $openWebUiHttp = Test-HttpEndpoint -Url $openWebUiUrl -TimeoutSeconds 5
    $managementHttp = Test-HttpEndpoint -Url $managementUrl -TimeoutSeconds 5
    $ttsHttp = if ($config.tts_enabled) {
        Test-HttpEndpoint -Url "$ttsUrl/docs" -TimeoutSeconds 5
    }
    else {
        $null
    }

    $tailscaleNodeInfo = $null
    $webUiServeState = $null
    $managementServeState = $null
    $tailscaleError = $null

    try {
        $tailscaleNodeInfo = Get-TailscaleNodeInfo
        $webUiServeState = Get-TailscaleServeState -Config $config
        $managementServeState = Get-TailscaleManagementServeState -Config $config
    }
    catch {
        $tailscaleError = $_.Exception.Message
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
        jobs = Get-HomelabManagerJobsSnapshot
    }
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
            $payload = (Convert-HomelabManagerJsonValue -Value (Get-HomelabManagerJobsSnapshot) | ConvertTo-Json -Depth 20 -Compress)

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

        if ([string]$body.secret -ne [string]$config.management_admin_secret) {
            Send-JsonResponse -Response $response -StatusCode 401 -Value ([ordered]@{
                error = "invalid_credentials"
                message = "The admin secret is incorrect."
            })
            return
        }

        $session = New-HomelabManagerSession
        Set-HomelabManagerSessionCookie -Response $response -Token ([string]$session.token)
        Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
            ok = $true
            expires_at = $session.expires_at
        })
        return
    }

    if ($Path -eq "/api/auth/logout" -and $method -eq "POST") {
        $token = Get-HomelabManagerRequestSessionToken -Request $request

        if (-not [string]::IsNullOrWhiteSpace($token)) {
            Remove-HomelabManagerSession -Token $token
        }

        Clear-HomelabManagerSessionCookie -Response $response
        Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
            ok = $true
        })
        return
    }

    if (-not (Assert-HomelabManagerAuthorizedRequest -Context $Context)) {
        return
    }

    switch ("$method $Path") {
        "GET /api/summary" {
            Send-JsonResponse -Response $response -StatusCode 200 -Value (Get-HomelabManagerSummary)
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
                    $ollamaPath = Get-OllamaPath
                    $removal = Remove-OllamaModels -OllamaPath $ollamaPath -Models @($diff.removed)
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

    $assetRoot = Join-Path $script:HomelabRoot "scripts\manager-ui"

    switch ($path) {
        "/" { Send-StaticFileResponse -Response $Context.Response -FilePath (Join-Path $assetRoot "index.html"); return }
        "/app.js" { Send-StaticFileResponse -Response $Context.Response -FilePath (Join-Path $assetRoot "app.js"); return }
        "/styles.css" { Send-StaticFileResponse -Response $Context.Response -FilePath (Join-Path $assetRoot "styles.css"); return }
        default {
            Send-JsonResponse -Response $Context.Response -StatusCode 404 -Value ([ordered]@{
                error = "not_found"
                message = "Route not found."
            })
            return
        }
    }
}
