function Test-IsWindowsPlatform {
    return ($env:OS -eq "Windows_NT")
}

function Test-IsAdministrator {
    if (-not (Test-IsWindowsPlatform)) {
        return $true
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-TailscaleAdminAccess {
    if (Test-IsAdministrator) {
        return
    }

    throw "Tailscale local API access on Windows requires an elevated PowerShell session. Re-run this script as Administrator and try again."
}

function Get-TailscalePath {
    $command = Get-Command "tailscale" -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    $candidatePaths = @(
        (Join-Path $env:ProgramFiles "Tailscale\tailscale.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Tailscale\tailscale.exe")
    )

    foreach ($candidatePath in $candidatePaths) {
        if ($candidatePath -and (Test-Path -LiteralPath $candidatePath)) {
            return $candidatePath
        }
    }

    throw "Tailscale CLI not found. Install Tailscale or add tailscale.exe to PATH."
}

function ConvertFrom-JsonOrThrow {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$InputText,

        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    if ([string]::IsNullOrWhiteSpace($InputText)) {
        return [pscustomobject]@{}
    }

    try {
        return $InputText | ConvertFrom-Json
    }
    catch {
        throw "$CommandName returned invalid JSON. Raw output: $InputText"
    }
}

function Invoke-TailscaleCommand {
    param(
        [string[]]$Arguments = @()
    )

    $tailscalePath = Get-TailscalePath
    $result = Invoke-NativeCommand -FilePath $tailscalePath -Arguments $Arguments

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()

        if ($message -match "Access is denied") {
            throw "Tailscale local API access was denied. Re-run this script as Administrator and try again."
        }

        throw $message
    }

    return $result
}

function Get-NormalizedTailscaleDnsName {
    param(
        [AllowEmptyString()]
        [string]$DnsName
    )

    if ([string]::IsNullOrWhiteSpace($DnsName)) {
        return ""
    }

    return $DnsName.Trim().TrimEnd(".")
}

function Get-TailscaleStatus {
    $result = Invoke-TailscaleCommand -Arguments @("status", "--json")
    return ConvertFrom-JsonOrThrow -InputText $result.StdOut -CommandName "tailscale status --json"
}

function Get-TailscaleNodeInfo {
    $status = Get-TailscaleStatus

    if (-not $status.Self) {
        throw "Tailscale is not fully initialized on this machine."
    }

    $dnsName = Get-NormalizedTailscaleDnsName -DnsName ([string]$status.Self.DNSName)

    if ([string]::IsNullOrWhiteSpace($dnsName)) {
        throw "Tailscale did not report a node DNS name. Enable MagicDNS for this tailnet and try again."
    }

    $certDomains = @()

    if ($null -ne $status.CertDomains) {
        $certDomains = @($status.CertDomains | ForEach-Object { Get-NormalizedTailscaleDnsName -DnsName ([string]$_) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return [pscustomobject]@{
        Status                    = $status
        DnsName                   = $dnsName
        HttpsUrl                  = "https://$dnsName"
        MagicDnsEnabled           = [bool]($status.CurrentTailnet -and $status.CurrentTailnet.MagicDNSEnabled)
        HttpsCertificatesEnabled  = ($certDomains.Count -gt 0)
        CertDomains               = $certDomains
    }
}

function Assert-TailscaleServePrerequisites {
    $nodeInfo = Get-TailscaleNodeInfo
    $status = $nodeInfo.Status

    if ([string]$status.BackendState -ne "Running") {
        throw "Tailscale is not running on this machine. Start Tailscale and try again."
    }

    if (-not $nodeInfo.MagicDnsEnabled) {
        throw "MagicDNS is not enabled for this tailnet. Enable MagicDNS in the Tailscale admin console DNS settings, then try again."
    }

    if (-not $nodeInfo.HttpsCertificatesEnabled) {
        throw "Tailscale HTTPS certificates are not enabled for this tailnet. In the Tailscale admin console, open DNS settings, enable HTTPS certificates, then re-run this script."
    }

    return $nodeInfo
}

function Get-TailscaleServeStatusJson {
    $result = Invoke-TailscaleCommand -Arguments @("serve", "status", "--json")
    return ConvertFrom-JsonOrThrow -InputText $result.StdOut -CommandName "tailscale serve status --json"
}

function Get-TailscaleServeConfigJson {
    $result = Invoke-TailscaleCommand -Arguments @("serve", "get-config", "--all", "-")
    return ConvertFrom-JsonOrThrow -InputText $result.StdOut -CommandName "tailscale serve get-config --all -"
}

function Get-ObjectPropertyNames {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        return @($InputObject.Keys)
    }

    return @($InputObject.PSObject.Properties | ForEach-Object { $_.Name })
}

function Test-IsSimpleValue {
    param(
        [object]$InputObject
    )

    return $null -eq $InputObject -or
        $InputObject -is [string] -or
        $InputObject.GetType().IsPrimitive -or
        $InputObject -is [decimal] -or
        $InputObject -is [datetime] -or
        $InputObject -is [guid]
}

function Test-ObjectHasProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    return (Get-ObjectPropertyNames -InputObject $InputObject) -contains $PropertyName
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject[$PropertyName]
    }

    return $InputObject.PSObject.Properties[$PropertyName].Value
}

function Get-RecursivePropertyValues {
    param(
        [object]$InputObject,
        [string]$PropertyName
    )

    $values = New-Object System.Collections.Generic.List[object]

    function Add-Matches {
        param(
            [object]$Node
        )

        if (Test-IsSimpleValue -InputObject $Node) {
            return
        }

        if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [System.Collections.IDictionary])) {
            foreach ($item in $Node) {
                Add-Matches -Node $item
            }

            return
        }

        foreach ($propertyName in (Get-ObjectPropertyNames -InputObject $Node)) {
            $propertyValue = Get-ObjectPropertyValue -InputObject $Node -PropertyName $propertyName

            if ($propertyName -eq $PropertyName) {
                $values.Add($propertyValue)
            }

            Add-Matches -Node $propertyValue
        }
    }

    Add-Matches -Node $InputObject
    return $values.ToArray()
}

function Test-TailscaleServeObjectHasHttps443 {
    param(
        [object]$InputObject
    )

    foreach ($tcpNode in (Get-RecursivePropertyValues -InputObject $InputObject -PropertyName "TCP")) {
        if ($null -eq $tcpNode -or -not (Test-ObjectHasProperty -InputObject $tcpNode -PropertyName "443")) {
            continue
        }

        $portNode = Get-ObjectPropertyValue -InputObject $tcpNode -PropertyName "443"

        if ($null -ne $portNode -and
            (Test-ObjectHasProperty -InputObject $portNode -PropertyName "HTTPS") -and
            [bool](Get-ObjectPropertyValue -InputObject $portNode -PropertyName "HTTPS")) {
            return $true
        }
    }

    return $false
}

function Test-TailscaleServeObjectHasExpectedWebProxy {
    param(
        [object]$InputObject,
        [string]$DnsName,
        [string]$ExpectedProxyTarget
    )

    foreach ($webNode in (Get-RecursivePropertyValues -InputObject $InputObject -PropertyName "Web")) {
        foreach ($hostKey in (Get-ObjectPropertyNames -InputObject $webNode)) {
            $normalizedHostKey = ([string]$hostKey).Trim().TrimEnd(".")

            if ($normalizedHostKey -ne "$DnsName`:443") {
                continue
            }

            $hostNode = Get-ObjectPropertyValue -InputObject $webNode -PropertyName $hostKey

            if ($null -eq $hostNode -or -not (Test-ObjectHasProperty -InputObject $hostNode -PropertyName "Handlers")) {
                continue
            }

            $handlers = Get-ObjectPropertyValue -InputObject $hostNode -PropertyName "Handlers"

            if ($null -eq $handlers -or -not (Test-ObjectHasProperty -InputObject $handlers -PropertyName "/")) {
                continue
            }

            $rootHandler = Get-ObjectPropertyValue -InputObject $handlers -PropertyName "/"

            if ($null -eq $rootHandler -or -not (Test-ObjectHasProperty -InputObject $rootHandler -PropertyName "Proxy")) {
                continue
            }

            if ([string](Get-ObjectPropertyValue -InputObject $rootHandler -PropertyName "Proxy") -eq $ExpectedProxyTarget) {
                return $true
            }
        }
    }

    return $false
}

function Test-TailscaleServeObjectHasExpectedWebProxyAnyHost {
    param(
        [object]$InputObject,
        [string]$ExpectedProxyTarget
    )

    foreach ($webNode in (Get-RecursivePropertyValues -InputObject $InputObject -PropertyName "Web")) {
        foreach ($hostKey in (Get-ObjectPropertyNames -InputObject $webNode)) {
            $hostNode = Get-ObjectPropertyValue -InputObject $webNode -PropertyName $hostKey

            if ($null -eq $hostNode -or -not (Test-ObjectHasProperty -InputObject $hostNode -PropertyName "Handlers")) {
                continue
            }

            $handlers = Get-ObjectPropertyValue -InputObject $hostNode -PropertyName "Handlers"

            if ($null -eq $handlers -or -not (Test-ObjectHasProperty -InputObject $handlers -PropertyName "/")) {
                continue
            }

            $rootHandler = Get-ObjectPropertyValue -InputObject $handlers -PropertyName "/"

            if ($null -eq $rootHandler -or -not (Test-ObjectHasProperty -InputObject $rootHandler -PropertyName "Proxy")) {
                continue
            }

            if ([string](Get-ObjectPropertyValue -InputObject $rootHandler -PropertyName "Proxy") -eq $ExpectedProxyTarget) {
                return $true
            }
        }
    }

    return $false
}

function Test-TailscaleServeObjectHasExpectedEndpoint {
    param(
        [object]$InputObject,
        [string]$ExpectedProxyTarget
    )

    foreach ($endpointsNode in (Get-RecursivePropertyValues -InputObject $InputObject -PropertyName "endpoints")) {
        if ($null -eq $endpointsNode -or -not (Test-ObjectHasProperty -InputObject $endpointsNode -PropertyName "tcp:443")) {
            continue
        }

        if ([string](Get-ObjectPropertyValue -InputObject $endpointsNode -PropertyName "tcp:443") -eq $ExpectedProxyTarget) {
            return $true
        }
    }

    return $false
}

function Test-TailscaleServeObjectHasAnyConfiguration {
    param(
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $false
    }

    $propertyNames = @()

    try {
        $propertyNames = @(Get-ObjectPropertyNames -InputObject $InputObject)
    }
    catch {
        return $false
    }

    if ($propertyNames.Count -eq 0) {
        return $false
    }

    if ($propertyNames.Count -eq 1 -and $propertyNames[0] -eq "version") {
        return $false
    }

    return $true
}

function Get-TailscaleServeState {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $nodeInfo = Get-TailscaleNodeInfo
    $expectedProxyTarget = "http://127.0.0.1:$($Config.openwebui_port)"
    $statusJson = Get-TailscaleServeStatusJson
    $configJson = Get-TailscaleServeConfigJson

    $hasHttps443 = (
        (Test-TailscaleServeObjectHasHttps443 -InputObject $statusJson) -or
        (Test-TailscaleServeObjectHasHttps443 -InputObject $configJson)
    )
    $hasExpectedTarget = (
        (Test-TailscaleServeObjectHasExpectedWebProxy -InputObject $statusJson -DnsName $nodeInfo.DnsName -ExpectedProxyTarget $expectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedWebProxy -InputObject $configJson -DnsName $nodeInfo.DnsName -ExpectedProxyTarget $expectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedEndpoint -InputObject $statusJson -ExpectedProxyTarget $expectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedEndpoint -InputObject $configJson -ExpectedProxyTarget $expectedProxyTarget)
    )
    $hasExpectedTargetAnyHost = (
        (Test-TailscaleServeObjectHasExpectedWebProxyAnyHost -InputObject $statusJson -ExpectedProxyTarget $expectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedWebProxyAnyHost -InputObject $configJson -ExpectedProxyTarget $expectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedEndpoint -InputObject $statusJson -ExpectedProxyTarget $expectedProxyTarget) -or
        (Test-TailscaleServeObjectHasExpectedEndpoint -InputObject $configJson -ExpectedProxyTarget $expectedProxyTarget)
    )
    $hasAnyConfiguration = (
        (Test-TailscaleServeObjectHasAnyConfiguration -InputObject $statusJson) -or
        (Test-TailscaleServeObjectHasAnyConfiguration -InputObject $configJson)
    )

    return [pscustomobject]@{
        NodeInfo             = $nodeInfo
        ExpectedProxyTarget  = $expectedProxyTarget
        HasAnyConfiguration  = $hasAnyConfiguration
        HasExpectedTargetAnyHost = $hasExpectedTargetAnyHost
        IsConfiguredExpected = ($hasHttps443 -and $hasExpectedTarget)
        StatusJson           = $statusJson
        ConfigJson           = $configJson
    }
}

function Enable-TailscaleOpenWebUiHttps {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $nodeInfo = Assert-TailscaleServePrerequisites
    $serveState = Get-TailscaleServeState -Config $Config

    if ($serveState.IsConfiguredExpected) {
        return $nodeInfo
    }

    if ($serveState.HasAnyConfiguration -and -not $serveState.HasExpectedTargetAnyHost) {
        throw "Tailscale Serve already has a different configuration on this machine. Clear or adjust the existing Serve config before enabling the repo-managed HTTPS mapping."
    }

    $target = $serveState.ExpectedProxyTarget
    [void](Invoke-TailscaleCommand -Arguments @("serve", "--bg", "--yes", "--https=443", $target))

    $updatedServeState = Get-TailscaleServeState -Config $Config

    if (-not $updatedServeState.IsConfiguredExpected) {
        throw "Tailscale HTTPS Serve did not end up with the expected proxy target ($target)."
    }

    return $nodeInfo
}

function Disable-TailscaleOpenWebUiHttps {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $serveState = Get-TailscaleServeState -Config $Config

    if (-not $serveState.IsConfiguredExpected) {
        return
    }

    [void](Invoke-TailscaleCommand -Arguments @("serve", "--yes", "--https=443", $serveState.ExpectedProxyTarget, "off"))
}
