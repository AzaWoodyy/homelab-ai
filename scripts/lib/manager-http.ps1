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
        403 { return "Forbidden" }
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

function Get-StaticContentType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    switch ([System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".mjs" { return "application/javascript; charset=utf-8" }
        ".json" { return "application/json; charset=utf-8" }
        ".map" { return "application/json; charset=utf-8" }
        ".svg" { return "image/svg+xml" }
        ".ico" { return "image/x-icon" }
        ".png" { return "image/png" }
        ".jpg" { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".webp" { return "image/webp" }
        ".woff" { return "font/woff" }
        ".woff2" { return "font/woff2" }
        ".txt" { return "text/plain; charset=utf-8" }
        ".webmanifest" { return "application/manifest+json; charset=utf-8" }
        default { return "application/octet-stream" }
    }
}

function Resolve-HomelabManagerStaticPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetRoot,

        [Parameter(Mandatory = $true)]
        [string]$RequestPath
    )

    $indexPath = Join-Path $AssetRoot "index.html"

    if ($RequestPath -eq "/" -or [string]::IsNullOrWhiteSpace($RequestPath)) {
        return [pscustomobject]@{
            Path      = $indexPath
            IsSpaPath = $true
        }
    }

    $relativePath = [System.Uri]::UnescapeDataString($RequestPath.TrimStart("/")).Replace("/", "\")
    $candidatePath = [System.IO.Path]::GetFullPath((Join-Path $AssetRoot $relativePath))
    $rootPath = [System.IO.Path]::GetFullPath($AssetRoot).TrimEnd("\")

    if (-not $candidatePath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
        return [pscustomobject]@{
            Path      = $candidatePath
            IsSpaPath = $false
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($candidatePath))) {
        return $null
    }

    return [pscustomobject]@{
        Path      = $indexPath
        IsSpaPath = $true
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
