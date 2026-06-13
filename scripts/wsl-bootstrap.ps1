param(
    [switch]$SkipGpuCheck
)

. (Join-Path $PSScriptRoot "common.ps1")

Initialize-HomelabScript -ScriptName "wsl-bootstrap"

$config = Get-HomelabConfig

if (-not (Test-HomelabContainerBackendWsl -Config $config) -and -not (Test-HomelabOllamaBackendWsl -Config $config)) {
    Write-Log "No WSL runtime backend is configured. Nothing to bootstrap." "OK"
    exit 0
}

function Get-LastNonEmptyTextLine {
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $nonEmptyLines = @(
        $Text -split "\r?\n" |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($nonEmptyLines.Count -eq 0) {
        return $null
    }

    return [string]$nonEmptyLines[-1]
}

function Invoke-WslBootstrapStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$CommandText
    )

    Write-Log $Description "STEP"
    $result = Invoke-WslShellCommand -Config $config -CommandText $CommandText -AsRoot

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()

        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "Command failed without output."
        }

        throw "$Description failed. $message"
    }

    $successMessage = Get-LastNonEmptyTextLine -Text $result.StdOut

    if (-not [string]::IsNullOrWhiteSpace($successMessage)) {
        Write-Log $successMessage "OK"
    }
    else {
        Write-Log "$Description completed." "OK"
    }
}

function Invoke-WslBootstrapNativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    return Invoke-NativeCommand -FilePath $FilePath -Arguments $Arguments
}

function Test-WslInstallAlreadyExistsMessage {
    param(
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    return ($Message -match "ERROR_ALREADY_EXISTS" -or $Message -match "(?i)already exists")
}

Write-Log "Checking WSL distro $($config.runtime_wsl_distro)..." "STEP"
$wslPath = Get-WslExecutablePath
$distroInfo = Get-WslDistroInfo -Config $config

if ($null -eq $distroInfo) {
    Write-Log "WSL distro $($config.runtime_wsl_distro) not found; requesting install." "WARN"
    $installResult = Invoke-WslBootstrapNativeCommand -FilePath $wslPath -Arguments @("--install", "-d", [string]$config.runtime_wsl_distro)

    if ($installResult.ExitCode -ne 0) {
        $message = ($installResult.StdErr + [Environment]::NewLine + $installResult.StdOut).Trim()

        if (Test-WslInstallAlreadyExistsMessage -Message $message) {
            $distroInfo = Get-WslDistroInfo -Config $config

            if ($null -ne $distroInfo) {
                Write-Log "WSL reported that distro $($config.runtime_wsl_distro) already exists; reusing the existing distro." "WARN"
            }
            else {
                throw "WSL reported that distro '$($config.runtime_wsl_distro)' already exists, but it still could not be found in 'wsl -l -v'. Run 'wsl -l -v' manually and rerun .\scripts\wsl-bootstrap.ps1."
            }
        }
        else {
            throw "WSL distro install failed. $message"
        }
    }

    if ($null -eq $distroInfo) {
        $distroInfo = Get-WslDistroInfo -Config $config
    }

    if ($null -eq $distroInfo) {
        $installMessage = ($installResult.StdErr + [Environment]::NewLine + $installResult.StdOut).Trim()

        if ($installMessage -match "(?i)reboot") {
            throw "WSL install requested a reboot before '$($config.runtime_wsl_distro)' becomes available. Reboot Windows, then rerun .\scripts\wsl-bootstrap.ps1."
        }

        throw "WSL install completed but distro '$($config.runtime_wsl_distro)' is still absent from 'wsl -l -v'. Reboot Windows or run 'wsl -d $($config.runtime_wsl_distro)' once to finish first-run Ubuntu setup, then rerun .\scripts\wsl-bootstrap.ps1."
    }
}
elseif ([int]$distroInfo.version -eq 2) {
    Write-Log "WSL distro $($config.runtime_wsl_distro) already exists; skipping install." "OK"
}
else {
    Write-Log "WSL distro $($config.runtime_wsl_distro) exists but is not WSL 2; upgrading to WSL 2." "WARN"
}

if ([int]$distroInfo.version -ne 2) {
    Write-Log "Ensuring WSL 2 is selected for $($config.runtime_wsl_distro)..." "STEP"
    $setVersionResult = Invoke-WslBootstrapNativeCommand -FilePath $wslPath -Arguments @("--set-version", [string]$config.runtime_wsl_distro, "2")

    if ($setVersionResult.ExitCode -ne 0) {
        $message = ($setVersionResult.StdErr + [Environment]::NewLine + $setVersionResult.StdOut).Trim()
        throw "Could not set WSL distro '$($config.runtime_wsl_distro)' to version 2. $message"
    }

    Write-Log "WSL distro is set to version 2." "OK"
    $distroInfo = Get-WslDistroInfo -Config $config
}

if ($null -eq $distroInfo) {
    throw "WSL distro '$($config.runtime_wsl_distro)' disappeared after install/version checks. Re-run 'wsl -l -v' and then rerun .\scripts\wsl-bootstrap.ps1."
}

if ([int]$distroInfo.version -ne 2) {
    throw "WSL distro '$($config.runtime_wsl_distro)' is still version $($distroInfo.version) after the upgrade attempt."
}

Write-Log "Probing WSL distro reachability..." "STEP"
try {
    Assert-WslDistroReady -Config $config
    Write-Log "WSL distro is reachable." "OK"
}
catch {
    throw $_.Exception.Message
}

$enableSystemdCommand = @'
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import re

path = Path("/etc/wsl.conf")
text = path.read_text(encoding="utf-8") if path.exists() else ""

if re.search(r"(?mi)^\s*systemd\s*=\s*true\s*$", text):
    print("systemd-already-enabled")
    raise SystemExit(0)

if re.search(r"(?mi)^\[boot\]\s*$", text):
    text = re.sub(r"(?mi)(^\[boot\]\s*$)", r"\1\nsystemd=true", text, count=1)
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += "[boot]\nsystemd=true\n"

path.write_text(text, encoding="utf-8")
print("systemd-enabled")
PY
'@

Invoke-WslBootstrapStep -Description "Enabling systemd inside WSL" -CommandText $enableSystemdCommand

Write-Log "Restarting WSL distro to apply systemd changes..." "STEP"
$terminateResult = Invoke-WslBootstrapNativeCommand -FilePath $wslPath -Arguments @("--terminate", [string]$config.runtime_wsl_distro)

if ($terminateResult.ExitCode -ne 0) {
    $message = ($terminateResult.StdErr + [Environment]::NewLine + $terminateResult.StdOut).Trim()

    if (-not [string]::IsNullOrWhiteSpace($message) -and $message -notmatch "There is no running instance") {
        throw "Failed to restart the WSL distro after enabling systemd. $message"
    }
}

Assert-WslDistroReady -Config $config
Write-Log "WSL distro is reachable after restart." "OK"

$dockerInstallCommand = @'
set -euo pipefail
install -m 0755 -d /etc/apt/keyrings
rm -f /etc/apt/sources.list.d/docker.list
if ! apt-get update; then
  echo "APT bootstrap refresh failed after Docker repo cleanup." >&2
  exit 1
fi
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg lsb-release zstd
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
fi
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
docker_repo_codename="${VERSION_CODENAME:-}"
if [ -z "$docker_repo_codename" ]; then
  docker_repo_codename="${UBUNTU_CODENAME:-}"
fi
if [ -z "$docker_repo_codename" ]; then
  docker_repo_codename="$(lsb_release -cs 2>/dev/null || true)"
fi
if [ -z "$docker_repo_codename" ]; then
  docker_repo_codename="$(python3 - <<'PY'
from pathlib import Path
import re

ubuntu_uri_patterns = (
    '://archive.ubuntu.com/ubuntu',
    '://security.ubuntu.com/ubuntu',
    '.archive.ubuntu.com/ubuntu',
)
suite_suffixes = ('-updates', '-backports', '-security', '-proposed')
suite_pattern = re.compile(r'^[a-z][a-z0-9-]*$')


def is_ubuntu_uri(value: str) -> bool:
    return any(pattern in value for pattern in ubuntu_uri_patterns)


def normalize_suite(value: str) -> str:
    suite = value.strip()

    if not suite or '/' in suite:
        suite = suite.split('/', 1)[0]

    for suffix in suite_suffixes:
        if suite.endswith(suffix):
            suite = suite[: -len(suffix)]
            break

    if suite_pattern.fullmatch(suite):
        return suite

    return ''


def iter_classic_suites(lines):
    for raw_line in lines:
        line = raw_line.strip()

        if not line or line.startswith('#') or not (line.startswith('deb ') or line.startswith('deb-src ')):
            continue

        parts = line.split()
        index = 1

        if index < len(parts) and parts[index].startswith('['):
            while index < len(parts) and not parts[index].endswith(']'):
                index += 1
            index += 1

        if index + 1 >= len(parts):
            continue

        uri = parts[index]
        suite = parts[index + 1]

        if is_ubuntu_uri(uri):
            yield suite


def iter_deb822_suites(paragraphs):
    for paragraph in paragraphs:
        uris = []
        suites = []

        for raw_line in paragraph.splitlines():
            line = raw_line.strip()

            if not line or line.startswith('#') or ':' not in line:
                continue

            key, value = line.split(':', 1)
            key = key.strip().lower()
            values = value.strip().split()

            if key == 'uris':
                uris.extend(values)
            elif key == 'suites':
                suites.extend(values)

        if uris and any(is_ubuntu_uri(uri) for uri in uris):
            for suite in suites:
                yield suite


candidate_paths = [Path('/etc/apt/sources.list')]
candidate_dir = Path('/etc/apt/sources.list.d')

if candidate_dir.exists():
    candidate_paths.extend(sorted(path for path in candidate_dir.iterdir() if path.is_file()))

for path in candidate_paths:
    try:
        text = path.read_text(encoding='utf-8')
    except (FileNotFoundError, IsADirectoryError, OSError, UnicodeDecodeError):
        continue

    suites = []

    if path.suffix == '.sources' or 'Suites:' in text:
        paragraphs = re.split(r'\n\s*\n', text)
        suites.extend(iter_deb822_suites(paragraphs))

    suites.extend(iter_classic_suites(text.splitlines()))

    for suite in suites:
        normalized = normalize_suite(suite)
        if normalized:
            print(normalized, end='')
            raise SystemExit(0)
PY
)"
fi
if [ -z "$docker_repo_codename" ]; then
  echo "Could not determine Ubuntu codename from /etc/os-release, lsb_release -cs, or Ubuntu APT sources." >&2
  exit 1
fi
docker_repo_arch="$(dpkg --print-architecture)"
docker_repo_line="deb [arch=${docker_repo_arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${docker_repo_codename} stable"
printf '%s\n' "$docker_repo_line" >/etc/apt/sources.list.d/docker.list
if ! apt-get update; then
  echo "Docker repo refresh failed after rewriting /etc/apt/sources.list.d/docker.list." >&2
  exit 1
fi
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
echo docker-ready
'@

Invoke-WslBootstrapStep -Description "Installing Docker Engine and Compose plugin in WSL" -CommandText $dockerInstallCommand

$defaultUserResult = Invoke-WslCommand -Config $config -Arguments @("sh", "-lc", "id -un")

if ($defaultUserResult.ExitCode -eq 0) {
    $defaultUser = (($defaultUserResult.StdOut -split "\r?\n") | Select-Object -First 1).Trim()

    if (-not [string]::IsNullOrWhiteSpace($defaultUser) -and $defaultUser -ne "root") {
        Invoke-WslBootstrapStep -Description "Adding default WSL user to the docker group" -CommandText "set -euo pipefail; usermod -aG docker $defaultUser; echo docker-group-updated"
    }
}

$ollamaInstallCommand = @'
set -euo pipefail
curl -fsSL https://ollama.com/install.sh | sh
systemctl enable ollama
echo ollama-ready
'@

Invoke-WslBootstrapStep -Description "Installing Ollama in WSL" -CommandText $ollamaInstallCommand

if (-not [string]::IsNullOrWhiteSpace([string]$config.ollama_models_runtime_path)) {
    $ollamaOverrideCommand = @"
set -euo pipefail
mkdir -p /etc/systemd/system/ollama.service.d
cat >/etc/systemd/system/ollama.service.d/homelab.conf <<'EOF'
[Service]
Environment="OLLAMA_MODELS=$($config.ollama_models_runtime_path)"
EOF
systemctl daemon-reload
echo ollama-models-path-configured
"@

    Invoke-WslBootstrapStep -Description "Configuring Ollama models path in WSL" -CommandText $ollamaOverrideCommand
}

Write-Log "Starting Docker and Ollama services in WSL..." "STEP"
Start-WslSystemService -Config $config -ServiceName "docker"
Start-WslSystemService -Config $config -ServiceName "ollama"
Write-Log "WSL services were started." "OK"

Write-Log "Validating Docker Engine in WSL..." "STEP"
$dockerVersion = Get-HomelabCommandSpecVersion -CommandSpec (Get-DockerCommandSpec -Config $config)
Write-Log $dockerVersion "OK"

Write-Log "Validating Ollama in WSL..." "STEP"
$ollamaVersion = Get-OllamaVersion -Config $config
Write-Log $ollamaVersion "OK"

Write-Log "Validating WSL service state..." "STEP"
$dockerServiceState = Get-WslSystemServiceState -Config $config -ServiceName "docker"
$ollamaServiceState = Get-WslSystemServiceState -Config $config -ServiceName "ollama"

if ($dockerServiceState -ne "active" -or $ollamaServiceState -ne "active") {
    throw "Expected docker and ollama to be active in WSL, but got docker=$dockerServiceState and ollama=$ollamaServiceState."
}

Write-Log "WSL service state: docker=$dockerServiceState, ollama=$ollamaServiceState" "OK"

Write-Log "Validating Ollama model store access..." "STEP"
Wait-ForOllamaReady -Config $config
$null = Get-InstalledOllamaModels -Config $config
Write-Log "Ollama is responding to model queries." "OK"

if ($SkipGpuCheck) {
    Write-Log "WSL GPU validation skipped." "WARN"
}
elseif (Test-WslNvidiaAvailable -Config $config) {
    Write-Log "NVIDIA CUDA is available inside WSL." "OK"
}
else {
    Write-Log "NVIDIA CUDA was not detected inside WSL. Docker and Ollama are configured, but this host is not GPU-ready yet." "WARN"
}

Write-Log "WSL Docker and Ollama bootstrap completed." "OK"
