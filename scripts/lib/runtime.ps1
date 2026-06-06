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

    $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ("homelab-ai-stdout-{0}.log" -f [guid]::NewGuid())
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("homelab-ai-stderr-{0}.log" -f [guid]::NewGuid())

    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList (Join-NativeArguments -Arguments $Arguments) `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stdout = if (Test-Path -LiteralPath $stdoutPath) {
            Get-Content -Raw -LiteralPath $stdoutPath
        }
        else {
            ""
        }

        $stderr = if (Test-Path -LiteralPath $stderrPath) {
            Get-Content -Raw -LiteralPath $stderrPath
        }
        else {
            ""
        }

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    }
    finally {
        if (Test-Path -LiteralPath $stdoutPath) {
            Remove-Item -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -ErrorAction SilentlyContinue
        }
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
