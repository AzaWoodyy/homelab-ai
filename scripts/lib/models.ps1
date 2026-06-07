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

function Save-ConfiguredModels {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Models
    )

    if ($null -eq $Models -or $Models.Count -eq 0) {
        throw "At least one model is required."
    }

    $normalizedModels = @()

    foreach ($model in $Models) {
        $modelName = [string]$model

        if ([string]::IsNullOrWhiteSpace($modelName)) {
            throw "Model entries cannot be empty."
        }

        $normalizedModels += $modelName.Trim()
    }

    $duplicates = $normalizedModels |
        ForEach-Object { Normalize-OllamaModelName -ModelName $_ } |
        Group-Object |
        Where-Object Count -gt 1 |
        Select-Object -ExpandProperty Name

    if ($duplicates) {
        throw "Duplicate models found after normalization: $($duplicates -join ', ')"
    }

    $configPath = Join-Path $script:HomelabRoot "config\models.json"
    $payload = [ordered]@{
        models = $normalizedModels
    }

    $json = $payload | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($configPath, ($json + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))

    return $normalizedModels
}

function Get-OllamaModelListDiff {
    param(
        [string[]]$CurrentModels = @(),
        [string[]]$DesiredModels = @()
    )

    $currentByNormalized = [ordered]@{}
    $desiredByNormalized = [ordered]@{}

    foreach ($model in @($CurrentModels)) {
        $normalized = Normalize-OllamaModelName -ModelName ([string]$model)

        if (-not [string]::IsNullOrWhiteSpace($normalized) -and -not $currentByNormalized.Contains($normalized)) {
            $currentByNormalized[$normalized] = ([string]$model).Trim()
        }
    }

    foreach ($model in @($DesiredModels)) {
        $normalized = Normalize-OllamaModelName -ModelName ([string]$model)

        if (-not [string]::IsNullOrWhiteSpace($normalized) -and -not $desiredByNormalized.Contains($normalized)) {
            $desiredByNormalized[$normalized] = ([string]$model).Trim()
        }
    }

    $added = @()
    $removed = @()
    $unchanged = @()

    foreach ($normalized in $desiredByNormalized.Keys) {
        if ($currentByNormalized.Contains($normalized)) {
            $unchanged += $desiredByNormalized[$normalized]
        }
        else {
            $added += $desiredByNormalized[$normalized]
        }
    }

    foreach ($normalized in $currentByNormalized.Keys) {
        if (-not $desiredByNormalized.Contains($normalized)) {
            $removed += $currentByNormalized[$normalized]
        }
    }

    return [ordered]@{
        added     = @($added)
        removed   = @($removed)
        unchanged = @($unchanged)
    }
}

function Remove-OllamaModels {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OllamaPath,

        [string[]]$Models = @()
    )

    $requested = @($Models | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    if ($requested.Count -eq 0) {
        return [ordered]@{
            requested = @()
            removed   = @()
            skipped   = @()
        }
    }

    if (-not (Test-OllamaReady -OllamaPath $OllamaPath)) {
        throw "Ollama is not responding, so removed models could not be uninstalled."
    }

    $installedModels = @(Get-InstalledOllamaModels -OllamaPath $OllamaPath)
    $installedNormalized = @{}

    foreach ($installedModel in $installedModels) {
        $normalizedInstalled = Normalize-OllamaModelName -ModelName $installedModel

        if (-not $installedNormalized.ContainsKey($normalizedInstalled)) {
            $installedNormalized[$normalizedInstalled] = $installedModel
        }
    }

    $removed = @()
    $skipped = @()

    foreach ($model in $requested) {
        $normalizedModel = Normalize-OllamaModelName -ModelName $model

        if (-not $installedNormalized.ContainsKey($normalizedModel)) {
            $skipped += $model
            continue
        }

        $removeResult = Invoke-NativeCommand -FilePath $OllamaPath -Arguments @("rm", $normalizedModel)

        if ($removeResult.ExitCode -ne 0) {
            $message = ($removeResult.StdErr + [Environment]::NewLine + $removeResult.StdOut).Trim()
            throw "Failed to uninstall Ollama model '$model'. $message"
        }

        $removed += $model
    }

    return [ordered]@{
        requested = @($requested)
        removed   = @($removed)
        skipped   = @($skipped)
    }
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
