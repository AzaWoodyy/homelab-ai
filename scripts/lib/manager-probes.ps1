function Add-HomelabManagerSummaryProbeError {
    param(
        [System.Collections.Generic.List[string]]$Errors,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($null -ne $Errors -and -not [string]::IsNullOrWhiteSpace($Message)) {
        [void]$Errors.Add($Message)
    }
}

function Invoke-HomelabManagerCommandSpecProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$CommandSpec,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMs,

        [System.Collections.Generic.List[string]]$Errors
    )

    try {
        $result = Invoke-HomelabCommandSpecWithTimeout -CommandSpec $CommandSpec -Arguments $Arguments -TimeoutMs $TimeoutMs

        if ($result.TimedOut) {
            Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "$Name timed out after $TimeoutMs ms."
            return $null
        }

        return $result
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "$Name failed: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-HomelabManagerNativeProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMs,

        [System.Collections.Generic.List[string]]$Errors
    )

    try {
        $result = Invoke-NativeCommandWithTimeout -FilePath $FilePath -Arguments $Arguments -TimeoutMs $TimeoutMs

        if ($result.TimedOut) {
            Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "$Name timed out after $TimeoutMs ms."
            return $null
        }

        return $result
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "$Name failed: $($_.Exception.Message)"
        return $null
    }
}

function Get-HomelabManagerOllamaVersionProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [System.Collections.Generic.List[string]]$Errors
    )

    $ollamaCommand = Get-OllamaCommandSpec -Config $Config
    $result = Invoke-HomelabManagerCommandSpecProbe -Name "Ollama version" -CommandSpec $ollamaCommand -Arguments $ollamaCommand.VersionArguments -TimeoutMs 5000 -Errors $Errors

    if ($null -eq $result -or $result.ExitCode -ne 0) {
        return $null
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
}

function Test-HomelabManagerOllamaReadyProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [System.Collections.Generic.List[string]]$Errors
    )

    $ollamaCommand = Get-OllamaCommandSpec -Config $Config
    $result = Invoke-HomelabManagerCommandSpecProbe -Name "Ollama list" -CommandSpec $ollamaCommand -Arguments @("list") -TimeoutMs 5000 -Errors $Errors
    return ($null -ne $result -and $result.ExitCode -eq 0)
}

function Get-HomelabManagerInstalledModelsProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [System.Collections.Generic.List[string]]$Errors
    )

    $ollamaCommand = Get-OllamaCommandSpec -Config $Config
    $result = Invoke-HomelabManagerCommandSpecProbe -Name "Installed model list" -CommandSpec $ollamaCommand -Arguments @("list") -TimeoutMs 7000 -Errors $Errors

    if ($null -eq $result -or $result.ExitCode -ne 0) {
        return @()
    }

    return ($result.StdOut -split "\r?\n") |
        Select-Object -Skip 1 |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { $_ } |
        ForEach-Object { ($_ -split '\s+')[0] }
}

function Test-HomelabManagerDockerReadyProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [System.Collections.Generic.List[string]]$Errors
    )

    $dockerCommand = Get-DockerCommandSpec -Config $Config
    $result = Invoke-HomelabManagerCommandSpecProbe -Name "Docker daemon" -CommandSpec $dockerCommand -Arguments @("info", "--format", "{{.ServerVersion}}") -TimeoutMs 5000 -Errors $Errors
    return ($null -ne $result -and $result.ExitCode -eq 0)
}

function Get-HomelabManagerContainerHealthProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [System.Collections.Generic.List[string]]$Errors
    )

    $dockerCommand = Get-DockerCommandSpec -Config $Config
    $result = Invoke-HomelabManagerCommandSpecProbe -Name "Container health $ContainerName" -CommandSpec $dockerCommand -Arguments @(
        "inspect",
        "--format",
        "{{if .State.Running}}{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}{{else}}stopped{{end}}",
        $ContainerName
    ) -TimeoutMs 5000 -Errors $Errors

    if ($null -eq $result) {
        return "unknown"
    }

    if ($result.ExitCode -ne 0) {
        return "missing"
    }

    return (($result.StdOut -split "\r?\n") | Select-Object -First 1).Trim()
}

function Invoke-HomelabManagerTailscaleJsonProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string[]]$Arguments = @(),

        [System.Collections.Generic.List[string]]$Errors
    )

    $result = Invoke-HomelabManagerNativeProbe -Name $Name -FilePath (Get-TailscalePath) -Arguments $Arguments -TimeoutMs 5000 -Errors $Errors

    if ($null -eq $result -or $result.ExitCode -ne 0) {
        return $null
    }

    try {
        return ConvertFrom-JsonOrThrow -InputText $result.StdOut -CommandName $Name
    }
    catch {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "$Name returned invalid JSON: $($_.Exception.Message)"
        return $null
    }
}

function Get-HomelabManagerTailscaleNodeInfoProbe {
    param(
        [System.Collections.Generic.List[string]]$Errors
    )

    $status = Invoke-HomelabManagerTailscaleJsonProbe -Name "tailscale status --json" -Arguments @("status", "--json") -Errors $Errors

    if ($null -eq $status -or -not $status.Self) {
        return $null
    }

    $dnsName = Get-NormalizedTailscaleDnsName -DnsName ([string]$status.Self.DNSName)

    if ([string]::IsNullOrWhiteSpace($dnsName)) {
        Add-HomelabManagerSummaryProbeError -Errors $Errors -Message "Tailscale did not report a node DNS name."
        return $null
    }

    $certDomains = @()
    $rawCertDomains = Get-HomelabObjectPropertyValue -InputObject $status -Name "CertDomains" -DefaultValue $null

    if ($null -ne $rawCertDomains) {
        $certDomains = @($rawCertDomains | ForEach-Object { Get-NormalizedTailscaleDnsName -DnsName ([string]$_) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return [pscustomobject]@{
        Status                   = $status
        DnsName                  = $dnsName
        HttpsUrl                 = "https://$dnsName"
        MagicDnsEnabled          = [bool]($status.CurrentTailnet -and $status.CurrentTailnet.MagicDNSEnabled)
        HttpsCertificatesEnabled = ($certDomains.Count -gt 0)
        CertDomains              = $certDomains
    }
}

function Get-HomelabManagerTailscaleServeProxyStateProbe {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$NodeInfo,

        [Parameter(Mandatory = $true)]
        [int]$HttpsPort,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedProxyTarget,

        [System.Collections.Generic.List[string]]$Errors
    )

    $statusJson = Invoke-HomelabManagerTailscaleJsonProbe -Name "tailscale serve status --json" -Arguments @("serve", "status", "--json") -Errors $Errors
    $configJson = Invoke-HomelabManagerTailscaleJsonProbe -Name "tailscale serve get-config --all -" -Arguments @("serve", "get-config", "--all", "-") -Errors $Errors

    if ($null -eq $statusJson -or $null -eq $configJson) {
        return $null
    }

    $hasHttpsPort = (
        (Test-TailscaleServeObjectHasHttpsPort -InputObject $statusJson -HttpsPort $HttpsPort) -or
        (Test-TailscaleServeObjectHasHttpsPort -InputObject $configJson -HttpsPort $HttpsPort)
    )
    $hasExpectedTarget = (
        (Test-TailscaleServeObjectHasExpectedWebProxy -InputObject $statusJson -DnsName $NodeInfo.DnsName -HttpsPort $HttpsPort -ExpectedProxyTarget $ExpectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedWebProxy -InputObject $configJson -DnsName $NodeInfo.DnsName -HttpsPort $HttpsPort -ExpectedProxyTarget $ExpectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedEndpoint -InputObject $statusJson -HttpsPort $HttpsPort -ExpectedProxyTarget $ExpectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedEndpoint -InputObject $configJson -HttpsPort $HttpsPort -ExpectedProxyTarget $ExpectedProxyTarget)
    )

    return [pscustomobject]@{
        IsConfiguredExpected = ($hasHttpsPort -and $hasExpectedTarget)
        ExpectedProxyTarget  = $ExpectedProxyTarget
        HttpsPort            = $HttpsPort
    }
}
