function Initialize-HomelabScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName
    )

    $logsPath = Join-Path $script:HomelabRoot "logs"

    if (-not (Test-Path -LiteralPath $logsPath)) {
        New-Item -ItemType Directory -Path $logsPath | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:CurrentLogPath = Join-Path $logsPath "$ScriptName-$timestamp.log"
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
