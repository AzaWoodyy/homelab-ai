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
