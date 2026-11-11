# Scripts

Every script lives in `scripts/` and loads the shared modules through `scripts/common.ps1`. Each run writes a timestamped log under `logs/` (ignored by git).

Run them from an elevated PowerShell session: Tailscale's local API usually needs Administrator rights.

## Stack lifecycle

`.\scripts\wsl-bootstrap.ps1`
- Installs or validates the configured WSL distro and enables systemd.
- Installs Docker Engine, the Docker Compose plugin and Ollama inside WSL.
- Points the WSL `ollama` service at `ollama.models_path` when it is set.
- Checks Docker, Ollama and NVIDIA CUDA visibility from WSL.
- Only needed when `runtime.container_backend` is `wsl-docker-engine` or `runtime.ollama_backend` is `wsl-service`.

`.\scripts\setup.ps1`
- Validates Docker and Ollama through the configured backend.
- Pulls the models listed in `config\models.json` that are missing locally.
- Pulls the local TTS image and warms the configured Piper voices once, so speech keeps working offline.
- When Hermes is enabled, validates the Hermes CLI, reports missing secrets and regenerates `state\hermes`.
- `-RefreshModels` re-pulls every configured model even if it is already installed.

`.\scripts\refresh-models.ps1`
- Shortcut for `setup.ps1 -RefreshModels`.

`.\scripts\start.ps1`
- Starts the Docker and Ollama backends.
- Starts Open WebUI and OpenedAI Speech with Docker Compose and waits until both answer over HTTP.
- Configures Tailscale Serve so Open WebUI is reachable over HTTPS on the tailnet.
- Starts the Hermes gateway when `hermes.enabled` is `true`.

`.\scripts\stop.ps1`
- Stops the Hermes gateway when it is enabled.
- Removes the repo-managed Tailscale Serve mapping.
- Stops Open WebUI and the TTS service (containers are kept, so the next start is fast).
- Stops Ollama.

`.\scripts\status.ps1`
- Quick, human-readable state of the stack, the manager and Hermes.

`.\scripts\test.ps1`
- End-to-end validation: config, models, Docker Compose, container health, Open WebUI health, direct TTS synthesis, TTS through the Open WebUI proxy, local HTTP reachability, Tailscale Serve config, remote HTTPS reachability and Hermes readiness.

`.\scripts\stack-install.ps1 [-StartNow]`
- Registers a Windows scheduled task that runs `stack-startup.ps1` at boot.

`.\scripts\stack-startup.ps1`
- Boot-time entry point: waits for Docker, then runs `start.ps1` with retries.

`.\scripts\sleep.ps1`, `.\scripts\shutdown.ps1`
- Stop the stack first, then queue a short delayed Windows sleep or shutdown so a manager job can finish cleanly.
- Waking the PC is handled outside this repo, see [Wake-on-LAN](./wake-on-lan.md).

## Remote manager

`.\scripts\manager-start.ps1`, `.\scripts\manager-stop.ps1`, `.\scripts\manager-restart.ps1`
- Start, stop or restart the manager service without touching Open WebUI, TTS or Ollama.
- Start also exposes the manager on the configured Tailscale HTTPS port (default `8443`).

`.\scripts\manager-install.ps1 [-StartNow]`, `.\scripts\manager-uninstall.ps1`
- Register or remove a user-logon scheduled task so the manager comes back after a reboot.

`.\scripts\manager-status.ps1`
- Manager process state, reachability, remote URL and pending apply actions.

`.\scripts\manager-test.ps1`
- Validates the landing page, SPA fallback, login flow, hardened session cookie, auth guard, CSRF protection and the authenticated summary API.

Internal entry points, started by the manager itself:

- `scripts\manager-service.ps1`: the HTTP service (static SPA + JSON API).
- `scripts\manager-job-runner.ps1`: runs one dashboard action at a time in its own process.
- `scripts\manager-summary-refresh.ps1`: refreshes the cached health summary in the background.

## Hermes Agent

`.\scripts\hermes-start.ps1`, `.\scripts\hermes-stop.ps1`, `.\scripts\hermes-restart.ps1`
- Manage only the Hermes gateway process, using the repo-local `HERMES_HOME`.
- Require Hermes Agent to be installed separately and available as `hermes` on `PATH`. See [hermes.md](./hermes.md).

## Developer checks

`.\scripts\check.ps1`
- Parses every tracked PowerShell script, validates the JSON files in `config/`, then runs `npm run check` (typecheck + Vitest) in `manager-ui/`.
- Does not start or touch the stack. CI runs the same steps.

Dashboard development:

```powershell
cd .\manager-ui
npm.cmd ci
npm.cmd run check   # typecheck + tests
npm.cmd run dev     # dev server on 127.0.0.1
npm.cmd run build   # writes manager-ui\dist, served by the manager service
```

## Troubleshooting WSL bootstrap

If the Docker step fails because the Ubuntu codename cannot be detected, list the active apt suites:

```powershell
wsl -d <your-distro> -- sh -lc "grep -RhsE '^(deb|Suites:)' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null"
```

Note the base codename (for example `resolute` from `resolute-updates`), remove the broken Docker source and rerun the bootstrap:

```powershell
wsl -d <your-distro> -- sudo rm -f /etc/apt/sources.list.d/docker.list
.\scripts\wsl-bootstrap.ps1
```
