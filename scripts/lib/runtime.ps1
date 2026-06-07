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

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = Join-NativeArguments -Arguments $Arguments
    $startInfo.UseShellExecute = $false
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

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
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
