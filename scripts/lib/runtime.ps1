function Join-NativeArgument {
    param(
        [AllowEmptyString()]
        [string]$Argument
    )

    if ($null -eq $Argument) {
        return '""'
    }

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $quoted = [System.Text.StringBuilder]::new()
    [void]$quoted.Append('"')
    $backslashCount = 0

    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }

        if ($character -eq '"') {
            [void]$quoted.Append('\' * (($backslashCount * 2) + 1))
            [void]$quoted.Append('"')
            $backslashCount = 0
            continue
        }

        if ($backslashCount -gt 0) {
            [void]$quoted.Append('\' * $backslashCount)
            $backslashCount = 0
        }

        [void]$quoted.Append($character)
    }

    if ($backslashCount -gt 0) {
        [void]$quoted.Append('\' * ($backslashCount * 2))
    }

    [void]$quoted.Append('"')
    return $quoted.ToString()
}

function Join-NativeArguments {
    param(
        [string[]]$Arguments = @()
    )

    return (($Arguments | ForEach-Object { Join-NativeArgument -Argument $_ }) -join " ")
}

function Normalize-NativeCommandText {
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return $Text
    }

    $normalized = $Text -replace "`0", ""
    return $normalized.TrimStart([char]0xFEFF)
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [AllowEmptyString()]
        [string]$StandardInputText
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = Join-NativeArguments -Arguments $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = ($PSBoundParameters.ContainsKey("StandardInputText"))
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.WorkingDirectory = (Get-Location).Path

    $environmentEntries = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in [System.Environment]::GetEnvironmentVariables().GetEnumerator()) {
        $environmentEntries[[string]$entry.Key] = [string]$entry.Value
    }

    if ($startInfo.PSObject.Properties.Name -contains "Environment" -and $null -ne $startInfo.Environment) {
        $startInfo.Environment.Clear()

        foreach ($key in $environmentEntries.Keys) {
            $startInfo.Environment[$key] = $environmentEntries[$key]
        }
    }
    else {
        foreach ($key in $environmentEntries.Keys) {
            $startInfo.EnvironmentVariables[$key] = $environmentEntries[$key]
        }
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if ($PSBoundParameters.ContainsKey("StandardInputText")) {
        $process.StandardInput.Write($StandardInputText)
        $process.StandardInput.Close()
    }

    $process.WaitForExit()
    $stdout = Normalize-NativeCommandText -Text ($stdoutTask.GetAwaiter().GetResult())
    $stderr = Normalize-NativeCommandText -Text ($stderrTask.GetAwaiter().GetResult())

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

function Invoke-NativeCommandWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMs
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = Join-NativeArguments -Arguments $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.WorkingDirectory = (Get-Location).Path

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutMs)) {
        try {
            $process.Kill()
        }
        catch {
        }

        $process.WaitForExit()
        $stdout = Normalize-NativeCommandText -Text ($stdoutTask.GetAwaiter().GetResult())
        $stderr = Normalize-NativeCommandText -Text ($stderrTask.GetAwaiter().GetResult())

        return [pscustomobject]@{
            ExitCode = $null
            StdOut   = $stdout
            StdErr   = $stderr
            TimedOut = $true
        }
    }

    $process.WaitForExit()
    $stdout = Normalize-NativeCommandText -Text ($stdoutTask.GetAwaiter().GetResult())
    $stderr = Normalize-NativeCommandText -Text ($stderrTask.GetAwaiter().GetResult())

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
        TimedOut = $false
    }
}

function Get-CommandVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandPath
    )

    $result = Invoke-NativeCommand -FilePath $CommandPath -Arguments @("--version")

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()
        throw $message
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
}

function Test-HomelabContainerBackendWsl {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return ([string]$Config.runtime_container_backend).Trim().ToLowerInvariant() -eq "wsl-docker-engine"
}

function Test-HomelabOllamaBackendWsl {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    return ([string]$Config.runtime_ollama_backend).Trim().ToLowerInvariant() -eq "wsl-service"
}

function Get-WslExecutablePath {
    $command = Get-Command "wsl.exe" -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    return (Join-Path $env:SystemRoot "System32\wsl.exe")
}

function Convert-WindowsPathToWslPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $trimmedPath = $Path.Trim()

    if ([string]::IsNullOrWhiteSpace($trimmedPath)) {
        return $trimmedPath
    }

    if ($trimmedPath.StartsWith("/")) {
        return $trimmedPath
    }

    $fullPath = [System.IO.Path]::GetFullPath($trimmedPath)

    if ($fullPath -notmatch '^[A-Za-z]:\\') {
        throw "Only drive-letter Windows paths can be translated into WSL paths: $Path"
    }

    $driveLetter = $fullPath.Substring(0, 1).ToLowerInvariant()
    $relativePath = $fullPath.Substring(2).Replace('\', '/').TrimStart('/')

    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        return "/mnt/$driveLetter"
    }

    return "/mnt/$driveLetter/$relativePath"
}

function Get-HomelabRepoRuntimePath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    if (Test-HomelabContainerBackendWsl -Config $Config) {
        return Convert-WindowsPathToWslPath -Path $script:HomelabRoot
    }

    return [System.IO.Path]::GetFullPath($script:HomelabRoot)
}

function Get-HomelabOllamaModelsRuntimePath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $modelsPath = [string]$Config.ollama_models_path

    if ([string]::IsNullOrWhiteSpace($modelsPath)) {
        return ""
    }

    if (Test-HomelabOllamaBackendWsl -Config $Config) {
        return Convert-WindowsPathToWslPath -Path $modelsPath
    }

    return [System.IO.Path]::GetFullPath($modelsPath)
}

function Get-WslCommandArguments {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [string[]]$Arguments = @(),

        [switch]$AsRoot
    )

    $distroName = [string]$Config.runtime_wsl_distro

    if ([string]::IsNullOrWhiteSpace($distroName)) {
        throw "runtime.wsl_distro must be configured when a WSL backend is selected."
    }

    $commandArguments = @("-d", $distroName)

    if ($AsRoot) {
        $commandArguments += @("-u", "root")
    }

    $commandArguments += "--"

    if ($Arguments) {
        $commandArguments += $Arguments
    }

    return $commandArguments
}

function Invoke-WslCommand {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [string[]]$Arguments = @(),

        [switch]$AsRoot
    )

    return Invoke-NativeCommand -FilePath (Get-WslExecutablePath) -Arguments (Get-WslCommandArguments -Config $Config -Arguments $Arguments -AsRoot:$AsRoot)
}

function Invoke-WslShellCommand {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$CommandText,

        [switch]$AsRoot
    )

    $normalizedCommandText = $CommandText

    if (-not [string]::IsNullOrEmpty($normalizedCommandText) -and -not $normalizedCommandText.EndsWith("`n")) {
        $normalizedCommandText += "`n"
    }

    return Invoke-NativeCommand `
        -FilePath (Get-WslExecutablePath) `
        -Arguments (Get-WslCommandArguments -Config $Config -Arguments @("bash", "-s", "--") -AsRoot:$AsRoot) `
        -StandardInputText $normalizedCommandText
}

function Get-WslDistroList {
    $result = Invoke-NativeCommand -FilePath (Get-WslExecutablePath) -Arguments @("-l", "-v")

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()
        throw "Failed to query WSL distros. $message"
    }

    $distros = @()

    foreach ($line in ($result.StdOut -split "\r?\n")) {
        $trimmedLine = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine -match '^NAME\s+' -or $trimmedLine -match '^The Windows Subsystem for Linux') {
            continue
        }

        if ($trimmedLine.StartsWith("*")) {
            $trimmedLine = $trimmedLine.Substring(1).Trim()
        }

        if ($trimmedLine -match '^(?<name>.+?)\s{2,}(?<state>\S+)\s+(?<version>\d+)$') {
            $distros += [pscustomobject]@{
                name    = [string]$Matches.name
                state   = [string]$Matches.state
                version = [int]$Matches.version
            }
        }
    }

    return @($distros)
}

function Get-WslDistroInfo {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $targetDistro = [string]$Config.runtime_wsl_distro

    foreach ($distro in @(Get-WslDistroList)) {
        if ($null -ne $distro -and -not [string]::IsNullOrWhiteSpace([string]$distro.name) -and ([string]$distro.name).Trim() -ieq $targetDistro) {
            return $distro
        }
    }

    return $null
}

function Get-WslReadyProbeErrorMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DistroName,

        [AllowEmptyString()]
        [string]$StdOut,

        [AllowEmptyString()]
        [string]$StdErr
    )

    $message = ($StdErr + [Environment]::NewLine + $StdOut).Trim()

    if ([string]::IsNullOrWhiteSpace($message)) {
        return "WSL distro '$DistroName' is not ready."
    }

    $needsInitializationPatterns = @(
        "Create a default Unix user account",
        "Enter new UNIX username",
        "installation successful",
        "launch it again to finish setup"
    )

    foreach ($pattern in $needsInitializationPatterns) {
        if ($message -imatch [regex]::Escape($pattern)) {
            return "WSL distro '$DistroName' exists but first-run Ubuntu setup is incomplete. Run 'wsl -d $DistroName' once, finish initialization, then rerun .\scripts\wsl-bootstrap.ps1."
        }
    }

    return "WSL distro '$DistroName' is not ready. $message"
}

function Assert-WslDistroReady {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $distroInfo = Get-WslDistroInfo -Config $Config

    if ($null -eq $distroInfo) {
        throw "WSL distro '$($Config.runtime_wsl_distro)' is not installed. Run .\scripts\wsl-bootstrap.ps1 first."
    }

    if ([int]$distroInfo.version -ne 2) {
        throw "WSL distro '$($Config.runtime_wsl_distro)' is version $($distroInfo.version), but WSL 2 is required."
    }

    $probeResult = Invoke-NativeCommandWithTimeout -FilePath (Get-WslExecutablePath) -Arguments (Get-WslCommandArguments -Config $Config -Arguments @("true")) -TimeoutMs 15000

    if ($probeResult.TimedOut) {
        throw "WSL distro '$($Config.runtime_wsl_distro)' did not answer the readiness probe within 15 seconds. Run 'wsl -d $($Config.runtime_wsl_distro) -- true' manually, then rerun .\scripts\wsl-bootstrap.ps1."
    }

    if ($probeResult.ExitCode -ne 0) {
        throw (Get-WslReadyProbeErrorMessage -DistroName ([string]$Config.runtime_wsl_distro) -StdOut $probeResult.StdOut -StdErr $probeResult.StdErr)
    }
}

function Start-WslSystemService {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    Assert-WslDistroReady -Config $Config
    $result = Invoke-WslCommand -Config $Config -Arguments @("systemctl", "start", $ServiceName) -AsRoot

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()
        throw "Failed to start WSL service '$ServiceName'. $message"
    }
}

function Get-WslSystemServiceState {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    Assert-WslDistroReady -Config $Config
    $result = Invoke-WslCommand -Config $Config -Arguments @("systemctl", "is-active", $ServiceName) -AsRoot

    if ($result.ExitCode -ne 0) {
        return "inactive"
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
}

function Test-WslNvidiaAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    try {
        Assert-WslDistroReady -Config $Config
        $result = Invoke-WslShellCommand -Config $Config -CommandText "command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1"
        return ($result.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}
