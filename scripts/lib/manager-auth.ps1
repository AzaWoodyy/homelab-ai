function New-HomelabManagerSessionToken {
    return New-HomelabManagerRandomToken
}

function Convert-HomelabBase64Url {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    return [Convert]::ToBase64String($Bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function New-HomelabManagerRandomToken {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    return Convert-HomelabBase64Url -Bytes $bytes
}

function Get-HomelabSha256Hex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()

    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Test-HomelabConstantTimeStringEqual {
    param(
        [AllowNull()]
        [string]$Left,

        [AllowNull()]
        [string]$Right
    )

    if ($null -eq $Left -or $null -eq $Right) {
        return $false
    }

    $leftBytes = [System.Text.Encoding]::UTF8.GetBytes($Left)
    $rightBytes = [System.Text.Encoding]::UTF8.GetBytes($Right)
    $maxLength = [Math]::Max($leftBytes.Length, $rightBytes.Length)
    $diff = $leftBytes.Length -bxor $rightBytes.Length

    for ($index = 0; $index -lt $maxLength; $index++) {
        $leftByte = if ($index -lt $leftBytes.Length) { $leftBytes[$index] } else { 0 }
        $rightByte = if ($index -lt $rightBytes.Length) { $rightBytes[$index] } else { 0 }
        $diff = $diff -bor ($leftByte -bxor $rightByte)
    }

    return $diff -eq 0
}

function Cleanup-HomelabManagerSessions {
    $now = Get-Date
    $remaining = @()

    foreach ($session in (Get-HomelabManagerSessions)) {
        if ($null -eq $session -or -not ($session.PSObject.Properties.Name -contains "token_hash")) {
            continue
        }

        $expiresAt = Get-Date ([string]$session.expires_at)

        if ($expiresAt -gt $now) {
            $remaining += $session
        }
    }

    Save-HomelabManagerSessions -Sessions $remaining
    return $remaining
}

function New-HomelabManagerSession {
    $sessions = Cleanup-HomelabManagerSessions
    $token = New-HomelabManagerSessionToken
    $session = [ordered]@{
        token_hash = Get-HomelabSha256Hex -Value $token
        csrf_token = New-HomelabManagerRandomToken
        created_at = Get-ManagerTimestamp
        expires_at = (Get-Date).AddHours(24).ToString("o")
    }

    $updated = @($sessions) + @($session)
    Save-HomelabManagerSessions -Sessions $updated
    $sessionWithToken = [ordered]@{
        token      = $token
        token_hash = $session.token_hash
        csrf_token = $session.csrf_token
        created_at = $session.created_at
        expires_at = $session.expires_at
    }

    return $sessionWithToken
}

function Remove-HomelabManagerSession {
    param(
        [string]$Token
    )

    $tokenHash = if ([string]::IsNullOrWhiteSpace($Token)) { "" } else { Get-HomelabSha256Hex -Value $Token }
    $sessions = Cleanup-HomelabManagerSessions | Where-Object { [string]$_.token_hash -ne $tokenHash }
    Save-HomelabManagerSessions -Sessions @($sessions)
}

function Get-HomelabManagerSession {
    param(
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $tokenHash = Get-HomelabSha256Hex -Value $Token

    foreach ($session in (Cleanup-HomelabManagerSessions)) {
        if (Test-HomelabConstantTimeStringEqual -Left ([string]$session.token_hash) -Right $tokenHash) {
            return $session
        }
    }

    return $null
}

function Get-HomelabManagerRequestSessionToken {
    param(
        [Parameter(Mandatory = $true)]
        $Request
    )

    $cookie = $Request.Cookies["homelab_manager_session"]

    if ($null -ne $cookie -and -not [string]::IsNullOrWhiteSpace($cookie.Value)) {
        return $cookie.Value
    }

    $authHeader = [string]$Request.Headers["Authorization"]

    if ($authHeader -match "^Bearer\s+(.+)$") {
        return $Matches[1].Trim()
    }

    return $null
}

function Test-HomelabManagerAuthorizedRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Request
    )

    $token = Get-HomelabManagerRequestSessionToken -Request $Request
    return $null -ne (Get-HomelabManagerSession -Token $token)
}

function Get-HomelabManagerAuthorizedSession {
    param(
        [Parameter(Mandatory = $true)]
        $Request
    )

    $token = Get-HomelabManagerRequestSessionToken -Request $Request
    return Get-HomelabManagerSession -Token $token
}

function Test-HomelabManagerCsrfRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Request,

        [Parameter(Mandatory = $true)]
        $Session
    )

    $method = $Request.HttpMethod.ToUpperInvariant()

    if ($method -in @("GET", "HEAD", "OPTIONS")) {
        return $true
    }

    $submittedToken = [string]$Request.Headers["X-CSRF-Token"]

    if ([string]::IsNullOrWhiteSpace($submittedToken)) {
        return $false
    }

    return Test-HomelabConstantTimeStringEqual -Left ([string]$Session.csrf_token) -Right $submittedToken
}

function Set-HomelabManagerSessionCookie {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        $Request,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$ExpiresAt
    )

    $expires = (Get-Date $ExpiresAt).ToUniversalTime().ToString("R", [System.Globalization.CultureInfo]::InvariantCulture)
    $maxAge = [Math]::Max(0, [int][Math]::Floor(((Get-Date $ExpiresAt) - (Get-Date)).TotalSeconds))
    $secure = if (Test-HomelabManagerHttpsRequest -Request $Request) { "; Secure" } else { "" }
    $cookieValue = "homelab_manager_session=$Token; Path=/; HttpOnly; SameSite=Strict; Expires=$expires; Max-Age=$maxAge$secure"
    $Response.Headers.Add("Set-Cookie", $cookieValue)
}

function Clear-HomelabManagerSessionCookie {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        $Request
    )

    $secure = if (Test-HomelabManagerHttpsRequest -Request $Request) { "; Secure" } else { "" }
    $Response.Headers.Add("Set-Cookie", "homelab_manager_session=; Path=/; HttpOnly; SameSite=Strict; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0$secure")
}

function Test-HomelabManagerHttpsRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Request
    )

    try {
        if ($Request.Url.Scheme -eq "https") {
            return $true
        }
    }
    catch {
    }

    $forwardedProto = [string]$Request.Headers["X-Forwarded-Proto"]

    if ($forwardedProto -match "(^|,\s*)https($|,)") {
        return $true
    }

    $forwarded = [string]$Request.Headers["Forwarded"]

    if ($forwarded -match "(?i)(^|[;,]\s*)proto=https($|[;,])") {
        return $true
    }

    return $false
}

function Assert-HomelabManagerAuthorizedRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    if (-not (Test-HomelabManagerAuthorizedRequest -Request $Context.Request)) {
        Send-JsonResponse -Response $Context.Response -StatusCode 401 -Value ([ordered]@{
            error = "unauthorized"
            message = "Authentication is required."
        })
        return $false
    }

    return $true
}

function Assert-HomelabManagerCsrfRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $session = Get-HomelabManagerAuthorizedSession -Request $Context.Request

    if ($null -eq $session -or -not (Test-HomelabManagerCsrfRequest -Request $Context.Request -Session $session)) {
        Send-JsonResponse -Response $Context.Response -StatusCode 403 -Value ([ordered]@{
            error = "csrf_failed"
            message = "A valid CSRF token is required."
        })
        return $false
    }

    return $true
}
