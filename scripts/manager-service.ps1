param()

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "manager-service"

$config = Get-HomelabConfig
Assert-ManagementAdminSecretConfigured -Config $config

function Read-TcpRequestLine {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream
    )

    $bytes = New-Object System.Collections.Generic.List[byte]

    while ($true) {
        $nextByte = $Stream.ReadByte()

        if ($nextByte -lt 0) {
            break
        }

        if ($nextByte -eq 10) {
            break
        }

        if ($nextByte -ne 13) {
            $bytes.Add([byte]$nextByte)
        }
    }

    return [System.Text.Encoding]::UTF8.GetString($bytes.ToArray())
}

function Convert-TcpCookieHeader {
    param(
        [string]$CookieHeader
    )

    $cookies = @{}

    if ([string]::IsNullOrWhiteSpace($CookieHeader)) {
        return $cookies
    }

    foreach ($segment in ($CookieHeader -split ';')) {
        $parts = $segment.Split('=', 2)

        if ($parts.Count -ne 2) {
            continue
        }

        $name = $parts[0].Trim()
        $value = $parts[1].Trim()

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $cookies[$name] = [pscustomobject]@{
                Value = $value
            }
        }
    }

    return $cookies
}

function Read-TcpRequestBytes {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory = $true)]
        [int]$Length
    )

    if ($Length -le 0) {
        return [byte[]]@()
    }

    $buffer = New-Object byte[] $Length
    $offset = 0

    while ($offset -lt $Length) {
        $bytesRead = $Stream.Read($buffer, $offset, $Length - $offset)

        if ($bytesRead -le 0) {
            throw "Unexpected end of request body."
        }

        $offset += $bytesRead
    }

    return $buffer
}

function Read-TcpChunkedRequestBody {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream
    )

    $bodyBuffer = New-Object System.IO.MemoryStream

    try {
        while ($true) {
            $sizeLine = Read-TcpRequestLine -Stream $Stream

            if ([string]::IsNullOrWhiteSpace($sizeLine)) {
                continue
            }

            $chunkSizeText = ($sizeLine.Split(';', 2)[0]).Trim()
            $chunkSize = 0

            if (-not [int]::TryParse($chunkSizeText, [System.Globalization.NumberStyles]::HexNumber, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$chunkSize)) {
                throw "Invalid chunk size: $sizeLine"
            }

            if ($chunkSize -eq 0) {
                while ($true) {
                    $trailerLine = Read-TcpRequestLine -Stream $Stream

                    if ([string]::IsNullOrEmpty($trailerLine)) {
                        break
                    }
                }

                break
            }

            $chunk = Read-TcpRequestBytes -Stream $Stream -Length $chunkSize
            $bodyBuffer.Write($chunk, 0, $chunk.Length)

            $chunkTerminator = Read-TcpRequestLine -Stream $Stream

            if ($chunkTerminator -ne "") {
                throw "Invalid chunk terminator."
            }
        }

        return $bodyBuffer.ToArray()
    }
    finally {
        $bodyBuffer.Dispose()
    }
}

function Read-TcpRequestContext {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.Sockets.TcpClient]$Client,

        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    $stream = $Client.GetStream()
    $Client.ReceiveTimeout = 10000
    $Client.SendTimeout = 10000
    $stream.ReadTimeout = 10000
    $stream.WriteTimeout = 10000
    $requestLine = Read-TcpRequestLine -Stream $stream

    if ([string]::IsNullOrWhiteSpace($requestLine)) {
        return $null
    }

    $requestParts = $requestLine.Split(' ')

    if ($requestParts.Count -lt 2) {
        throw "Invalid HTTP request line: $requestLine"
    }

    $method = $requestParts[0].Trim().ToUpperInvariant()
    $rawPath = $requestParts[1].Trim()
    $headers = @{}

    while ($true) {
        $line = Read-TcpRequestLine -Stream $stream

        if ([string]::IsNullOrEmpty($line)) {
            break
        }

        $separatorIndex = $line.IndexOf(':')

        if ($separatorIndex -lt 1) {
            continue
        }

        $headerName = $line.Substring(0, $separatorIndex).Trim()
        $headerValue = $line.Substring($separatorIndex + 1).Trim()
        $headers[$headerName] = $headerValue
    }

    $contentLength = 0
    [void][int]::TryParse([string]$headers["Content-Length"], [ref]$contentLength)
    $transferEncoding = [string]$headers["Transfer-Encoding"]
    $bodyBytes = [byte[]]@()

    if (-not [string]::IsNullOrWhiteSpace($transferEncoding) -and $transferEncoding.ToLowerInvariant().Contains("chunked")) {
        $bodyBytes = Read-TcpChunkedRequestBody -Stream $stream
    }
    elseif ($contentLength -gt 0) {
        $bodyBytes = Read-TcpRequestBytes -Stream $stream -Length $contentLength
    }

    $body = [System.Text.Encoding]::UTF8.GetString($bodyBytes)

    $uri = [System.Uri]::new("http://127.0.0.1:$Port$rawPath")
    $request = [pscustomobject]@{
        HttpMethod      = $method
        Url             = $uri
        RawUrl          = $rawPath
        Headers         = $headers
        Cookies         = Convert-TcpCookieHeader -CookieHeader ($headers["Cookie"])
        Body            = $body
        ContentEncoding = [System.Text.Encoding]::UTF8
    }
    $response = [pscustomobject]@{
        Headers = [ordered]@{}
        Stream  = $stream
        Client  = $Client
    }

    return [pscustomobject]@{
        Request  = $request
        Response = $response
    }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $config.management_port)
$listener.Start()

Write-HomelabManagerLockInfo -ProcessId $PID -Port $config.management_port
Write-Log "Homelab manager listening on http://127.0.0.1:$($config.management_port)/" "OK"

$requestHandler = Get-HomelabManagerRequestHandlerScript
$runspacePool = [runspacefactory]::CreateRunspacePool(1, 8)
$runspacePool.Open()
$workers = New-Object System.Collections.Generic.List[object]

function Clear-CompletedManagerWorkers {
    $completedWorkers = @($workers.ToArray() | Where-Object { $_.Handle.IsCompleted })

    foreach ($worker in $completedWorkers) {
        try {
            $worker.PowerShell.EndInvoke($worker.Handle) | Out-Null
        }
        catch {
        }
        finally {
            $worker.PowerShell.Dispose()
            [void]$workers.Remove($worker)
        }
    }
}

function Stop-StaleManagerWorkers {
    $now = Get-Date

    foreach ($worker in $workers.ToArray()) {
        if ($worker.Handle.IsCompleted) {
            continue
        }

        if ([string]$worker.Path -ne "/api/jobs/stream") {
            continue
        }

        if ((($now - $worker.StartedAt).TotalMinutes) -lt 6) {
            continue
        }

        try {
            $worker.PowerShell.Stop()
        }
        catch {
        }
    }
}

try {
    while ($true) {
        if (-not $listener.Pending()) {
            Clear-CompletedManagerWorkers
            Stop-StaleManagerWorkers
            Start-Sleep -Milliseconds 200
            continue
        }

        $client = $listener.AcceptTcpClient()

        try {
            $context = Read-TcpRequestContext -Client $client -Port $config.management_port
        }
        catch {
            try {
                $client.Close()
            }
            catch {
            }

            continue
        }

        if ($null -eq $context) {
            try {
                $client.Close()
            }
            catch {
            }

            continue
        }

        $powerShell = [powershell]::Create()
        $powerShell.RunspacePool = $runspacePool
        [void]$powerShell.AddScript($requestHandler.ToString()).AddArgument($context).AddArgument($script:HomelabRoot)
        $handle = $powerShell.BeginInvoke()
        $workers.Add([pscustomobject]@{
            PowerShell = $powerShell
            Handle     = $handle
            Path       = $context.Request.Url.AbsolutePath
            StartedAt  = Get-Date
        }) | Out-Null
        Clear-CompletedManagerWorkers
        Stop-StaleManagerWorkers
    }
}
catch {
    try {
        Write-Log "Homelab manager main loop failed: $($_.Exception.Message)" "ERROR"
    }
    catch {
    }

    throw
}
finally {
    try {
        $listener.Stop()
    }
    catch {
    }

    Clear-CompletedManagerWorkers

    foreach ($worker in $workers.ToArray()) {
        try {
            $worker.PowerShell.Dispose()
        }
        catch {
        }
    }

    try {
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
    catch {
    }

    Remove-HomelabManagerLockInfo
}
