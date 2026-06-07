param()

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "manager-test"

$config = Get-HomelabConfig
Assert-ManagementAdminSecretConfigured -Config $config

$localUrl = Get-HomelabManagerLocalUrl -Config $config
$cookieJar = Join-Path ([System.IO.Path]::GetTempPath()) ("homelab-manager-cookie-{0}.txt" -f [guid]::NewGuid())
$managerUri = [System.Uri]$localUrl

function Invoke-RawManagerRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestText
    )

    $client = [System.Net.Sockets.TcpClient]::new($managerUri.Host, $managerUri.Port)

    try {
        $stream = $client.GetStream()
        $stream.ReadTimeout = 10000
        $stream.WriteTimeout = 10000
        $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
        $writer.NewLine = "`r`n"
        $writer.Write($RequestText)
        $writer.Flush()

        $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false))

        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
            $writer.Dispose()
        }
    }
    finally {
        $client.Close()
    }
}

try {
    Write-Log "Checking manager landing page..." "STEP"
    $rootResponse = Test-HttpEndpoint -Url $localUrl -TimeoutSeconds 10

    if (-not $rootResponse.Ok) {
        throw "Homelab manager is not reachable at $localUrl."
    }

    Write-Log "Manager landing page is reachable (HTTP $($rootResponse.StatusCode))." "OK"

    Write-Log "Checking unauthorized API rejection..." "STEP"
    $unauthorizedResult = Invoke-NativeCommand -FilePath "curl.exe" -Arguments @(
        "-sS",
        "-o",
        "NUL",
        "-w",
        "%{http_code}",
        "$localUrl/api/summary"
    )

    if ($unauthorizedResult.ExitCode -ne 0 -or ($unauthorizedResult.StdOut.Trim() -ne "401")) {
        throw "Expected /api/summary to return HTTP 401 before login."
    }

    Write-Log "Unauthorized API access is rejected with HTTP 401." "OK"

    Write-Log "Checking login flow..." "STEP"
    $loginResult = Invoke-NativeCommand -FilePath "curl.exe" -Arguments @(
        "-sS",
        "-c",
        $cookieJar,
        "-H",
        "Content-Type: application/json",
        "-d",
        "{""secret"":""$($config.management_admin_secret)""}",
        "$localUrl/api/auth/login"
    )

    if ($loginResult.ExitCode -ne 0 -or $loginResult.StdOut -notmatch '"ok"\s*:\s*true') {
        throw "Manager login failed."
    }

    Write-Log "Manager login succeeded." "OK"

    Write-Log "Checking authenticated summary endpoint..." "STEP"
    $summaryResult = Invoke-NativeCommand -FilePath "curl.exe" -Arguments @(
        "-sS",
        "-b",
        $cookieJar,
        "$localUrl/api/summary"
    )

    if ($summaryResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($summaryResult.StdOut)) {
        throw "Authenticated summary request returned an empty response."
    }

    if ($summaryResult.StdOut -notmatch '"manager"' -or $summaryResult.StdOut -notmatch '"stack"') {
        throw "Authenticated summary response is missing expected sections."
    }

    Write-Log "Authenticated summary endpoint returned JSON." "OK"

    Write-Log "Checking chunked login flow..." "STEP"
    $loginBody = "{""secret"":""$($config.management_admin_secret)""}"
    $chunkedRequest = @(
        "POST /api/auth/login HTTP/1.1"
        "Host: $($managerUri.Host):$($managerUri.Port)"
        "Content-Type: application/json"
        "Transfer-Encoding: chunked"
        "Connection: close"
        ""
        ("{0:x}" -f ([System.Text.Encoding]::UTF8.GetByteCount($loginBody)))
        $loginBody
        "0"
        ""
        ""
    ) -join "`r`n"
    $chunkedLoginResponse = Invoke-RawManagerRequest -RequestText $chunkedRequest

    if ($chunkedLoginResponse -notmatch "^HTTP/1\.1 200 ") {
        throw "Chunked manager login did not return HTTP 200."
    }

    $chunkedCookieMatch = [regex]::Match($chunkedLoginResponse, "Set-Cookie:\s*(homelab_manager_session=[^;\r\n]+)")

    if (-not $chunkedCookieMatch.Success) {
        throw "Chunked manager login did not return a session cookie."
    }

    $summaryRequest = @(
        "GET /api/summary HTTP/1.1"
        "Host: $($managerUri.Host):$($managerUri.Port)"
        "Cookie: $($chunkedCookieMatch.Groups[1].Value)"
        "Connection: close"
        ""
        ""
    ) -join "`r`n"
    $chunkedSummaryResponse = Invoke-RawManagerRequest -RequestText $summaryRequest

    if ($chunkedSummaryResponse -notmatch "^HTTP/1\.1 200 " -or $chunkedSummaryResponse -notmatch '"manager"' -or $chunkedSummaryResponse -notmatch '"stack"') {
        throw "Chunked login session could not reach the authenticated summary endpoint."
    }

    Write-Log "Chunked login flow returned an authenticated summary." "OK"
    Write-Log "Homelab manager validation checks passed." "OK"
}
finally {
    Remove-FileIfPresent -Path $cookieJar
}
