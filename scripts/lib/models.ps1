function Normalize-OllamaModelName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelName
    )

    $normalized = $ModelName.Trim()

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $normalized
    }

    $lastSlashIndex = $normalized.LastIndexOf("/")
    $lastColonIndex = $normalized.LastIndexOf(":")

    if ($lastColonIndex -gt $lastSlashIndex) {
        return $normalized
    }

    return "$normalized`:latest"
}

function Get-ConfiguredModels {
    $configPath = Join-Path $script:HomelabRoot "config\models.json"

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Model config file not found: $configPath"
    }

    $rawConfig = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json

    if ($null -eq $rawConfig.models -or $rawConfig.models.Count -eq 0) {
        throw "config/models.json must contain at least one model."
    }

    $models = @()

    foreach ($model in $rawConfig.models) {
        $modelName = [string]$model

        if ([string]::IsNullOrWhiteSpace($modelName)) {
            throw "config/models.json contains an empty model entry."
        }

        $models += $modelName.Trim()
    }

    $duplicates = $models |
        ForEach-Object { Normalize-OllamaModelName -ModelName $_ } |
        Group-Object |
        Where-Object Count -gt 1 |
        Select-Object -ExpandProperty Name

    if ($duplicates) {
        throw "Duplicate models found in config/models.json after normalization: $($duplicates -join ', ')"
    }

    return $models
}

function Assert-ConfiguredModelsInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ConfiguredModels,

        [Parameter(Mandatory = $true)]
        [string[]]$InstalledModels
    )

    $normalizedInstalledModels = $InstalledModels |
        ForEach-Object { Normalize-OllamaModelName -ModelName $_ } |
        Select-Object -Unique

    $missingModels = $ConfiguredModels | Where-Object {
        (Normalize-OllamaModelName -ModelName $_) -notin $normalizedInstalledModels
    }

    if ($missingModels) {
        throw "Missing configured models: $($missingModels -join ', ')"
    }
}
