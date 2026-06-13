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

    Write-Log "Checking static SPA fallback..." "STEP"
    $spaFallbackResult = Invoke-NativeCommand -FilePath "curl.exe" -Arguments @(
        "-sS",
        "-o",
        "NUL",
        "-w",
        "%{http_code}",
        "$localUrl/config"
    )

    if ($spaFallbackResult.ExitCode -ne 0 -or ($spaFallbackResult.StdOut.Trim() -ne "200")) {
        throw "Expected SPA fallback route to return HTTP 200."
    }

    Write-Log "Static SPA fallback is reachable." "OK"

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
        "-i",
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

    if ($loginResult.StdOut -notmatch "Set-Cookie:\s*homelab_manager_session=[^;\r\n]+;[^\r\n]*Path=/[^\r\n]*HttpOnly[^\r\n]*SameSite=Strict[^\r\n]*Expires=[^;\r\n]+;[^\r\n]*Max-Age=\d+") {
        throw "Manager login did not return the expected hardened session cookie attributes."
    }

    if ($loginResult.StdOut -match "Set-Cookie:\s*homelab_manager_session=[^\r\n]*;\s*Secure") {
        throw "Local HTTP login should not mark the session cookie Secure."
    }

    $csrfMatch = [regex]::Match($loginResult.StdOut, '"csrf_token"\s*:\s*"([^"]+)"')

    if (-not $csrfMatch.Success) {
        throw "Manager login did not return a CSRF token."
    }

    $csrfToken = $csrfMatch.Groups[1].Value
    Write-Log "Manager login succeeded with hardened cookie attributes." "OK"

    Write-Log "Checking session endpoint..." "STEP"
    $sessionResult = Invoke-NativeCommand -FilePath "curl.exe" -Arguments @(
        "-sS",
        "-b",
        $cookieJar,
        "$localUrl/api/auth/session"
    )

    if ($sessionResult.ExitCode -ne 0 -or $sessionResult.StdOut -notmatch '"ok"\s*:\s*true' -or $sessionResult.StdOut -notmatch '"csrf_token"') {
        throw "Authenticated session endpoint did not return the expected JSON."
    }

    Write-Log "Session endpoint returned the active CSRF token." "OK"

    Write-Log "Checking authenticated summary endpoint..." "STEP"
    $summaryTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $summaryResult = Invoke-NativeCommand -FilePath "curl.exe" -Arguments @(
        "-sS",
        "-b",
        $cookieJar,
        "$localUrl/api/summary"
    )
    $summaryTimer.Stop()

    if ($summaryResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($summaryResult.StdOut)) {
        throw "Authenticated summary request returned an empty response."
    }

    if ($summaryResult.StdOut -notmatch '"manager"' -or $summaryResult.StdOut -notmatch '"stack"') {
        throw "Authenticated summary response is missing expected sections."
    }

    if ($summaryResult.StdOut -notmatch '"meta"' -or $summaryTimer.Elapsed.TotalSeconds -gt 3) {
        throw "Authenticated summary should return cache-backed metadata within 3 seconds. Elapsed: $([math]::Round($summaryTimer.Elapsed.TotalSeconds, 2))s."
    }

    Write-Log "Authenticated summary endpoint returned cache-backed JSON in $([math]::Round($summaryTimer.Elapsed.TotalSeconds, 2))s." "OK"

    Write-Log "Checking summary refresh CSRF rejection..." "STEP"
    $summaryRefreshRejectResult = Invoke-NativeCommand -FilePath "curl.exe" -Arguments @(
        "-sS",
        "-o",
        "NUL",
        "-w",
        "%{http_code}",
        "-b",
        $cookieJar,
        "-X",
        "POST",
        "$localUrl/api/summary/refresh"
    )

    if ($summaryRefreshRejectResult.ExitCode -ne 0 -or ($summaryRefreshRejectResult.StdOut.Trim() -ne "403")) {
        throw "Expected summary refresh without CSRF token to return HTTP 403."
    }

    Write-Log "Summary refresh rejects missing CSRF tokens." "OK"

    Write-Log "Checking summary refresh CSRF acceptance..." "STEP"
    $summaryRefreshAcceptResult = Invoke-NativeCommand -FilePath "curl.exe" -Arguments @(
        "-sS",
        "-w",
        "`n%{http_code}",
        "-b",
        $cookieJar,
        "-H",
        "Content-Type: application/json",
        "-H",
        "X-CSRF-Token: $csrfToken",
        "-d",
        "{}",
        "$localUrl/api/summary/refresh"
    )

    if ($summaryRefreshAcceptResult.ExitCode -ne 0 -or $summaryRefreshAcceptResult.StdOut -notmatch '"meta"' -or -not $summaryRefreshAcceptResult.StdOut.TrimEnd().EndsWith("202")) {
        throw "Expected summary refresh with CSRF token to return HTTP 202 and summary metadata."
    }

    Write-Log "Summary refresh accepts valid CSRF tokens." "OK"

    Write-Log "Checking CSRF rejection..." "STEP"
    $csrfRejectResult = Invoke-NativeCommand -FilePath "curl.exe" -Arguments @(
        "-sS",
        "-o",
        "NUL",
        "-w",
        "%{http_code}",
        "-b",
        $cookieJar,
        "-X",
        "POST",
        "$localUrl/api/auth/logout"
    )

    if ($csrfRejectResult.ExitCode -ne 0 -or ($csrfRejectResult.StdOut.Trim() -ne "403")) {
        throw "Expected logout without CSRF token to return HTTP 403."
    }

    Write-Log "Mutating API requests reject missing CSRF tokens." "OK"

    Write-Log "Checking CSRF acceptance..." "STEP"
    $csrfAcceptResult = Invoke-NativeCommand -FilePath "curl.exe" -Arguments @(
        "-sS",
        "-o",
        "NUL",
        "-w",
        "%{http_code}",
        "-b",
        $cookieJar,
        "-H",
        "Content-Type: application/json",
        "-H",
        "X-CSRF-Token: $csrfToken",
        "-d",
        "{}",
        "$localUrl/api/auth/logout"
    )

    if ($csrfAcceptResult.ExitCode -ne 0 -or ($csrfAcceptResult.StdOut.Trim() -ne "200")) {
        throw "Expected logout with CSRF token to return HTTP 200."
    }

    Write-Log "Mutating API requests accept valid CSRF tokens." "OK"

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

    $sessionRequest = @(
        "GET /api/auth/session HTTP/1.1"
        "Host: $($managerUri.Host):$($managerUri.Port)"
        "Cookie: $($chunkedCookieMatch.Groups[1].Value)"
        "Connection: close"
        ""
        ""
    ) -join "`r`n"
    $chunkedSessionResponse = Invoke-RawManagerRequest -RequestText $sessionRequest

    if ($chunkedSessionResponse -notmatch "^HTTP/1\.1 200 " -or $chunkedSessionResponse -notmatch '"ok"\s*:\s*true' -or $chunkedSessionResponse -notmatch '"csrf_token"') {
        throw "Chunked login session could not reach the authenticated session endpoint."
    }

    Write-Log "Chunked login flow returned an authenticated session." "OK"
    Write-Log "Homelab manager validation checks passed." "OK"
}
finally {
    Remove-FileIfPresent -Path $cookieJar
}
