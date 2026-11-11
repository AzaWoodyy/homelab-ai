function Send-HomelabManagerJobStream {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    if ($Response.PSObject.Properties.Name -contains "OutputStream") {
        Set-ResponseCommonHeaders -Response $Response
        $Response.StatusCode = 200
        $Response.ContentType = "text/event-stream"
        $Response.Headers["Connection"] = "keep-alive"
        $stream = $Response.OutputStream
    }
    else {
        Set-ResponseCommonHeaders -Response $Response
        $Response.Headers["Content-Type"] = "text/event-stream; charset=utf-8"
        $Response.Headers["Connection"] = "keep-alive"
        $headerBuilder = [System.Text.StringBuilder]::new()
        [void]$headerBuilder.Append("HTTP/1.1 200 OK`r`n")

        foreach ($headerName in $Response.Headers.Keys) {
            [void]$headerBuilder.Append("${headerName}: $($Response.Headers[$headerName])`r`n")
        }

        [void]$headerBuilder.Append("`r`n")
        $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerBuilder.ToString())
        $Response.Stream.Write($headerBytes, 0, $headerBytes.Length)
        $Response.Stream.Flush()
        $stream = $Response.Stream
    }

    $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
    $lastPayload = ""
    $heartbeatIntervalSeconds = 10
    $streamLifetimeMinutes = 5

    try {
        $startedAt = Get-Date
        $lastHeartbeatAt = $startedAt

        while (((Get-Date) - $startedAt).TotalMinutes -lt $streamLifetimeMinutes) {
            $payload = (Convert-HomelabManagerJsonValue -Value (Get-HomelabManagerFastJobsSnapshot) | ConvertTo-Json -Depth 20 -Compress)

            if ($payload -ne $lastPayload) {
                $writer.Write("event: update`n")
                $writer.Write("data: $payload`n`n")
                $writer.Flush()
                $lastPayload = $payload
                $lastHeartbeatAt = Get-Date
            }
            elseif (((Get-Date) - $lastHeartbeatAt).TotalSeconds -ge $heartbeatIntervalSeconds) {
                $writer.Write(": keepalive`n`n")
                $writer.Flush()
                $lastHeartbeatAt = Get-Date
            }

            Start-Sleep -Milliseconds 1000
        }
    }
    catch {
    }
    finally {
        try {
            $writer.Dispose()
        }
        catch {
        }

        try {
            Close-HomelabManagerResponse -Response $Response
        }
        catch {
        }
    }
}

function Handle-HomelabManagerApiRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $request = $Context.Request
    $response = $Context.Response
    $method = $request.HttpMethod.ToUpperInvariant()

    if ($Path -eq "/api/auth/login" -and $method -eq "POST") {
        $config = Get-HomelabConfig
        Assert-ManagementAdminSecretConfigured -Config $config
        $retryAfterSeconds = Get-HomelabManagerLoginRetryAfterSeconds

        if ($retryAfterSeconds -gt 0) {
            Send-JsonResponse -Response $response -StatusCode 429 -Value ([ordered]@{
                error               = "too_many_attempts"
                message             = "Too many failed sign-in attempts. Try again in $retryAfterSeconds seconds."
                retry_after_seconds = $retryAfterSeconds
            })
            return
        }

        $body = Read-RequestBodyJson -Request $request
        $submittedSecretHash = Get-HomelabSha256Hex -Value ([string]$body.secret)
        $expectedSecretHash = Get-HomelabSha256Hex -Value ([string]$config.management_admin_secret)

        if (-not (Test-HomelabConstantTimeStringEqual -Left $submittedSecretHash -Right $expectedSecretHash)) {
            Register-HomelabManagerLoginFailure
            Send-JsonResponse -Response $response -StatusCode 401 -Value ([ordered]@{
                error = "invalid_credentials"
                message = "The admin secret is incorrect."
            })
            return
        }

        Reset-HomelabManagerLoginThrottle
        $session = New-HomelabManagerSession
        Set-HomelabManagerSessionCookie -Response $response -Request $request -Token ([string]$session.token) -ExpiresAt ([string]$session.expires_at)
        Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
            ok         = $true
            expires_at = $session.expires_at
            csrf_token = $session.csrf_token
        })
        return
    }

    if (-not (Assert-HomelabManagerAuthorizedRequest -Context $Context)) {
        return
    }

    if ($method -notin @("GET", "HEAD", "OPTIONS") -and -not (Assert-HomelabManagerCsrfRequest -Context $Context)) {
        return
    }

    switch ("$method $Path") {
        "GET /api/auth/session" {
            $session = Get-HomelabManagerAuthorizedSession -Request $request
            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                ok         = $true
                expires_at = $session.expires_at
                csrf_token = $session.csrf_token
            })
            return
        }
        "POST /api/auth/logout" {
            $token = Get-HomelabManagerRequestSessionToken -Request $request

            if (-not [string]::IsNullOrWhiteSpace($token)) {
                Remove-HomelabManagerSession -Token $token
            }

            Clear-HomelabManagerSessionCookie -Response $response -Request $request
            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                ok = $true
            })
            return
        }
        "GET /api/summary" {
            Send-JsonResponse -Response $response -StatusCode 200 -Value (Get-HomelabManagerSummary)
            return
        }
        "POST /api/summary/refresh" {
            Send-JsonResponse -Response $response -StatusCode 202 -Value (Request-HomelabManagerSummaryRefresh)
            return
        }
        "GET /api/config" {
            Send-JsonResponse -Response $response -StatusCode 200 -Value (Get-HomelabManagerConfigResponse)
            return
        }
        "PUT /api/config" {
            $before = Get-EditableHomelabConfig | ConvertTo-Json -Depth 20 -Compress
            $body = Read-RequestBodyJson -Request $request
            $savedConfig = Save-EditableHomelabConfig -EditableConfig $body
            $after = $savedConfig | ConvertTo-Json -Depth 20 -Compress
            $pendingApply = if ($before -ne $after) {
                Set-HomelabManagerPendingApplyState -ConfigChanged $true -ModelsChanged $false
            }
            else {
                Get-HomelabManagerPendingApplyState
            }

            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                editable      = $savedConfig
                read_only     = Get-HomelabManagerReadOnlyConfig
                pending_apply = $pendingApply
            })
            return
        }
        "GET /api/models" {
            Send-JsonResponse -Response $response -StatusCode 200 -Value (Get-HomelabManagerModelsResponse)
            return
        }
        "GET /api/hermes" {
            Send-JsonResponse -Response $response -StatusCode 200 -Value (Get-HermesSummary -Config (Get-HomelabConfig))
            return
        }
        "PUT /api/models" {
            $body = Read-RequestBodyJson -Request $request

            if ($null -eq $body.models) {
                throw "The request body must contain a 'models' array."
            }

            $config = Get-HomelabConfig
            $beforeModels = @(Get-ConfiguredModels)
            $diff = Get-OllamaModelListDiff -CurrentModels $beforeModels -DesiredModels @($body.models)
            $uninstallRemoved = [bool]$body.uninstall_removed
            $savedModels = Save-ConfiguredModels -Models @($body.models)
            $modelsChanged = (@($diff.added).Count -gt 0 -or @($diff.removed).Count -gt 0)

            $uninstallResult = [ordered]@{
                requested = $uninstallRemoved
                removed   = @()
                skipped   = @()
                error     = $null
            }

            if ($uninstallRemoved -and @($diff.removed).Count -gt 0) {
                try {
                    $removal = Remove-OllamaModels -Config $config -Models @($diff.removed)
                    $uninstallResult.removed = @($removal.removed)
                    $uninstallResult.skipped = @($removal.skipped)
                }
                catch {
                    $uninstallResult.error = $_.Exception.Message
                }
            }

            $pendingApply = if ($modelsChanged) {
                Set-HomelabManagerPendingApplyState -ConfigChanged $false -ModelsChanged $true -AddedModels @($diff.added) -RemovedModels @($diff.removed)
            }
            else {
                Get-HomelabManagerPendingApplyState
            }

            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                configured        = @($savedModels)
                installed         = @((Get-HomelabManagerModelsResponse).installed)
                pending_apply     = $pendingApply
                added_models      = @($diff.added)
                removed_models    = @($diff.removed)
                uninstall_removed = $uninstallRemoved
                uninstall_result  = $uninstallResult
            })
            return
        }
        "GET /api/jobs/current" {
            $snapshot = Get-HomelabManagerJobsSnapshot
            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                current       = $snapshot.current
                latest        = $snapshot.latest
                pending_apply = $snapshot.pending_apply
            })
            return
        }
        "GET /api/jobs/history" {
            $snapshot = Get-HomelabManagerJobsSnapshot
            Send-JsonResponse -Response $response -StatusCode 200 -Value ([ordered]@{
                history = $snapshot.history
            })
            return
        }
        "GET /api/jobs/stream" {
            Send-HomelabManagerJobStream -Response $response
            return
        }
    }

    if ($method -eq "POST" -and $Path.StartsWith("/api/actions/")) {
        $actionName = $Path.Substring("/api/actions/".Length)
        $job = Start-HomelabManagerActionJob -ActionName $actionName
        Send-JsonResponse -Response $response -StatusCode 202 -Value ([ordered]@{
            accepted = $true
            job      = $job
        })
        return
    }

    Send-JsonResponse -Response $response -StatusCode 404 -Value ([ordered]@{
        error = "not_found"
        message = "The requested API endpoint does not exist."
    })
}

function Handle-HomelabManagerRequest {
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $request = $Context.Request
    $path = $request.Url.AbsolutePath

    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = "/"
    }

    if ($path.StartsWith("/api/")) {
        Handle-HomelabManagerApiRequest -Context $Context -Path $path
        return
    }

    $assetRoot = Join-Path $script:HomelabRoot "manager-ui\dist"
    $resolvedAsset = Resolve-HomelabManagerStaticPath -AssetRoot $assetRoot -RequestPath $path

    if ($null -eq $resolvedAsset) {
        Send-JsonResponse -Response $Context.Response -StatusCode 404 -Value ([ordered]@{
            error = "not_found"
            message = "Asset not found."
        })
        return
    }

    Send-StaticFileResponse -Response $Context.Response -FilePath ([string]$resolvedAsset.Path)
    return
}
