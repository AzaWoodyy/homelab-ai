function Initialize-HomelabScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName
    )

    Set-HomelabProcessEnvironment -Config (Get-HomelabConfig)

    $logsPath = Join-Path $script:HomelabRoot "logs"

    if (-not (Test-Path -LiteralPath $logsPath)) {
        New-Item -ItemType Directory -Path $logsPath | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($env:HOMELAB_LOG_PATH)) {
        $overridePath = [System.IO.Path]::GetFullPath($env:HOMELAB_LOG_PATH)
        $overrideDirectory = Split-Path -Parent $overridePath

        if (-not [string]::IsNullOrWhiteSpace($overrideDirectory) -and -not (Test-Path -LiteralPath $overrideDirectory)) {
            New-Item -ItemType Directory -Path $overrideDirectory -Force | Out-Null
        }

        $script:CurrentLogPath = $overridePath
        return
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:CurrentLogPath = Join-Path $logsPath "$ScriptName-$timestamp.log"
}

function Get-CurrentLogPath {
    return $script:CurrentLogPath
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "STEP", "OK", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        "STEP" { "Cyan" }
        "OK" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        default { "Gray" }
    }

    Write-Host $line -ForegroundColor $color

    if ($script:CurrentLogPath) {
        Add-Content -LiteralPath $script:CurrentLogPath -Value $line
    }
}
