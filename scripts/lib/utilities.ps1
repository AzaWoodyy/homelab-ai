function Get-HomelabObjectPropertyValue {
    param(
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($Name)) {
        return $InputObject[$Name]
    }

    $property = $InputObject.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Set-HomelabObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [object]$Value
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        $InputObject[$Name] = $Value
        return
    }

    $property = $InputObject.PSObject.Properties[$Name]

    if ($null -eq $property) {
        $InputObject | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
        return
    }

    $property.Value = $Value
}

function Get-HomelabNestedPropertyValue {
    param(
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string[]]$Path,

        [object]$DefaultValue = $null
    )

    $current = $InputObject

    foreach ($name in $Path) {
        if ($null -eq $current) {
            return $DefaultValue
        }

        $current = Get-HomelabObjectPropertyValue -InputObject $current -Name $name -DefaultValue $null
    }

    if ($null -eq $current) {
        return $DefaultValue
    }

    return $current
}

function Ensure-HomelabNestedObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $value = Get-HomelabObjectPropertyValue -InputObject $InputObject -Name $Name -DefaultValue $null

    if ($null -eq $value) {
        $value = [pscustomobject]@{}
        Set-HomelabObjectPropertyValue -InputObject $InputObject -Name $Name -Value $value
    }

    return $value
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
        [object]$Value,

        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $Path

    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $json = $Value | ConvertTo-Json -Depth $Depth
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

function Get-HomelabRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $normalizedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if ($fullPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($normalizedRoot.Length).TrimStart('\')
    }

    return $fullPath
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
