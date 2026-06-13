# Homelab AI

Homelab AI is a personal self-hosted AI workspace for coding, research, and small automation workflows.

The current stack is intentionally simple:

- Ubuntu runs inside WSL 2 and hosts Docker Engine plus Ollama.
- Open WebUI runs in Docker and connects to Ollama through `host.docker.internal`.
- OpenedAI Speech runs in Docker for local text-to-speech.
- Hermes Agent can run as an optional local messaging gateway for Discord, Photon iMessage, and an OpenAI-compatible agent API.
- Tailscale is the private remote access and HTTPS layer.
- A PowerShell manager service provides a remote control dashboard.
- PowerShell scripts remain the operator surface on Windows and call Docker/Ollama through `wsl.exe`.

## What This Repo Tries To Do

- Stay private by default.
- Be easy to understand and easy to stop.
- Keep local inference on one powerful PC.
- Let laptops and phones reach the UI through Tailscale.
- Avoid heavyweight infrastructure until it is clearly needed.

## How It Works

The main chat path is:

`Laptop or phone -> Tailscale -> Gaming PC -> Open WebUI -> Ollama -> Local model`

The speech path is:

`Microphone -> Open WebUI STT (local Whisper) -> Ollama model -> OpenedAI Speech (Piper) -> Speaker`

The Hermes messaging path is:

`Discord or iMessage -> Hermes gateway -> Hermes Agent -> Ollama/Hermes model + configured tools`

A few practical notes:

- Ollama runs on Windows by default and can reuse the configured local models path.
- Docker Desktop is the default container runtime path for this repo.
- Open WebUI runs in Docker on port `3000` by default, but that port is only bound to `127.0.0.1`.
- OpenedAI Speech runs in Docker on port `8000` by default, and that port is also only bound to `127.0.0.1`.
- The manager service listens on `127.0.0.1:3081` by default.
- When enabled, Hermes uses `state/hermes` as `HERMES_HOME`, keeps generated Hermes `.env` and `config.yaml` files there, and runs as a host-native hidden user process.
- Hermes API server defaults to `127.0.0.1:8642` and can be added to Open WebUI as an OpenAI-compatible connection named `Hermes Agent`.
- Docker data is stored in a named volume, so Open WebUI users and chats persist across normal stop/start cycles.
- Piper voice files are stored in a Docker volume after the first setup warmup, so TTS can stay local and offline after setup.
- Open WebUI sometimes falls back to OpenAI-style voice ids such as `alloy` in the speaker UI. This repo maps those aliases back to local Piper voices so TTS still stays local.
- Local speech-to-text uses Whisper `medium` by default with language auto-detect.
- When you change `stt.model`, run `.\scripts\setup.ps1` once while internet is available so the new Whisper snapshot is cached for offline use.
- Remote access is intended to use the Tailscale HTTPS URL for this machine, such as `https://<machine>.<tailnet>.ts.net`.
- The manager dashboard is intended to use the same machine name on a dedicated HTTPS port, such as `https://<machine>.<tailnet>.ts.net:8443`.

## Tailscale HTTPS Prerequisites

Remote microphone and speaker-related browser APIs usually require a secure context, which means plain `http://...:3000` is not enough on other devices.

Before using the remote URL, make sure:

- Tailscale is installed on this PC and on each client device.
- Every client device is signed in to the same tailnet.
- MagicDNS is enabled for the tailnet.
- HTTPS certificates are enabled in the Tailscale admin console DNS settings.
- You run the repo PowerShell scripts from an elevated PowerShell session on Windows, because Tailscale local API access may require Administrator privileges.

When Tailscale HTTPS certificates are enabled, the machine name and tailnet DNS name become visible in certificate transparency logs. That is expected behavior for public CA-issued certificates.

## Wake-on-LAN Companion

Wake-on-LAN is now treated as a companion workflow rather than part of this repo's supported runtime surface.

If you want the gaming PC to wake reliably before you connect to it:

- Complete the target PC and network prerequisites in [Wake-on-LAN Setup Guide](./docs/wake-on-lan.md).
- Run the dedicated relay service on a separate always-on LAN node.
- Keep that relay project outside this repo so the homelab stack stays focused on the gaming PC runtime.

The remote wake path is:

`Phone or laptop -> Tailscale -> Wake Relay -> Magic packet -> Gaming PC`

## Quick Start

Initial setup:

```powershell
.\scripts\wsl-bootstrap.ps1
```

Repo setup:

```powershell
.\scripts\setup.ps1
```

Start the stack:

```powershell
.\scripts\start.ps1
```

Check health:

```powershell
.\scripts\test.ps1
```

Run developer checks:

```powershell
.\scripts\check.ps1
```

Start the remote manager:

```powershell
.\scripts\manager-start.ps1
```

Start only Hermes Agent after enabling it:

```powershell
.\scripts\hermes-start.ps1
```

Check manager health:

```powershell
.\scripts\manager-test.ps1
```

Stop the stack:

```powershell
.\scripts\stop.ps1
```

## Script Guide

`.\scripts\setup.ps1`
- Validates Docker and Ollama through the configured backend.
- Reads configured models from `config\models.json`.
- Pulls only missing models.
- Reuses `config\homelab.local.json` `ollama.models_path` when you want Ollama model blobs to live outside the default WSL root filesystem.
- Pulls the local TTS image and warms the configured Piper voices once.
- When Hermes is enabled, validates the Hermes CLI, checks local secrets, and syncs generated Hermes runtime config under `state\hermes`.

`.\scripts\setup.ps1 -RefreshModels`
- Re-pulls configured models even if they are already installed.

`.\scripts\start.ps1`
- Starts the configured Docker backend and Ollama backend.
- Starts Open WebUI and the local TTS service with Docker Compose.
- Waits until both local HTTP services are reachable.
- Configures Tailscale Serve so the remote URL is HTTPS on the tailnet.
- Starts the Hermes gateway when `hermes.enabled` is true.

`.\scripts\stop.ps1`
- Stops the Hermes gateway when `hermes.enabled` is true.
- Removes the repo-managed Tailscale HTTPS mapping.
- Stops Open WebUI and the local TTS service.
- Stops Ollama.

`.\scripts\test.ps1`
- Verifies config, models, Docker Compose, Open WebUI health, local TTS health, direct TTS synthesis, Open WebUI TTS proxy synthesis, local HTTP reachability, Tailscale Serve config, and remote HTTPS reachability.

`.\scripts\check.ps1`
- Runs lightweight developer checks without starting the stack.
- Parses tracked PowerShell scripts, validates repo config JSON files, and runs the manager UI TypeScript/Vitest check.

`.\scripts\wsl-bootstrap.ps1`
- Installs or validates the configured WSL distro.
- Enables systemd in WSL.
- Installs Docker Engine, Docker Compose plugin, and Ollama in WSL.
- Configures the Ollama systemd service to reuse the configured models path when `ollama.models_path` is set.
- Verifies Docker, Ollama, and optional NVIDIA CUDA visibility in WSL.

If the Docker step still fails because the Ubuntu codename cannot be detected, use this recovery path and rerun bootstrap:

```powershell
wsl -d <your-distro> -- sh -lc "grep -RhsE '^(deb|Suites:)' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null"
```

Look for the active Ubuntu suite such as `resolute`, `resolute-updates`, `resolute-backports`, or `resolute-security`, and use the base codename without the suffix.

```powershell
wsl -d <your-distro> -- sudo rm -f /etc/apt/sources.list.d/docker.list
.\scripts\wsl-bootstrap.ps1
```

`.\scripts\status.ps1`
- Shows the current stack state in a quick human-readable form.

`.\scripts\refresh-models.ps1`
- Convenience wrapper for `setup.ps1 -RefreshModels`.

`.\scripts\hermes-start.ps1`, `.\scripts\hermes-stop.ps1`, `.\scripts\hermes-restart.ps1`
- Manage only the Hermes gateway process.
- Use the repo-local `HERMES_HOME` from `config\homelab.json`.
- Require Hermes Agent to be installed separately and available as `hermes` on PATH.

`.\scripts\manager-install.ps1 -StartNow`
- Registers the manager as a Windows user-logon Scheduled Task and starts it immediately.

`.\scripts\manager-start.ps1`
- Starts the host-native manager service on the local machine.
- Tries to expose the manager on the configured Tailscale HTTPS port.

`.\scripts\manager-stop.ps1`
- Stops only the manager control surface and removes its Tailscale HTTPS mapping.

`.\scripts\manager-restart.ps1`
- Restarts the manager service without touching Open WebUI, TTS, or Ollama.

`.\scripts\manager-status.ps1`
- Shows the manager process state, reachability, remote URL, and pending apply actions.

`.\scripts\manager-test.ps1`
- Verifies the manager landing page, login flow, auth guard, and authenticated summary API.
- Also checks the React SPA fallback, hardened session cookie attributes, session endpoint, and CSRF protection.

Manager UI development:

```powershell
cd .\scripts\manager-ui
npm.cmd install
npm.cmd run check
npm.cmd run dev
npm.cmd run build
```

The manager service serves the production build from `scripts\manager-ui\dist`.

`.\scripts\sleep.ps1`
- Stops the homelab stack first.
- Queues a short delayed Windows sleep transition so the manager job can finish cleanly before the host sleeps.

`.\scripts\shutdown.ps1`
- Stops the homelab stack first.
- Queues a short delayed Windows shutdown so the manager job can finish cleanly before the host powers off.

The manager UI exposes the same sleep and shutdown actions.
Wake stays outside this repo and remains the responsibility of the separate Wake Relay companion app.

## Config

Main runtime config lives in `config\homelab.json`:

```json
{
  "hostname": "homelab-ai",
  "openwebui_port": 3000,
  "openwebui_image_tag": "v0.9.6",
  "openwebui": {
    "mcp_initialize_timeout": 30,
    "kb_exec_enabled": false,
    "profile_image_max_data_uri_size": null
  },
  "runtime": {
    "container_backend": "windows-docker",
    "wsl_distro": "Ubuntu",
    "ollama_backend": "windows-process"
  },
  "management": {
    "port": 3081,
    "tailscale_https_port": 8443
  },
  "hermes": {
    "enabled": false,
    "home": "state\\hermes",
    "model": "hermes3:8b",
    "gateway": {
      "enabled": true
    },
    "api_server": {
      "enabled": true,
      "host": "127.0.0.1",
      "port": 8642,
      "model_name": "Hermes Agent"
    },
    "discord": {
      "enabled": true,
      "require_mention": true,
      "free_response_channels": ""
    },
    "photon": {
      "enabled": true,
      "sidecar_port": 8789,
      "sidecar_autostart": true,
      "require_mention": false,
      "mention_patterns": ""
    }
  },
  "tts": {
    "enabled": true,
    "port": 8000,
    "default_voice": "fr_FR-siwis-medium",
    "fallback_voice": "en_US-lessac-medium"
  },
  "stt": {
    "model": "medium",
    "language": "",
    "auto_update": false
  }
}
```

`hostname` can still be kept for compatibility, but the secure remote URL is discovered from Tailscale at runtime and should be treated as the source of truth for browser access.

The `openwebui` block exposes a small set of repo-managed advanced settings:

- `mcp_initialize_timeout`: increases the MCP handshake timeout for slower local tool servers.
- `kb_exec_enabled`: turns the built-in knowledge base filesystem tool on or off.
- `profile_image_max_data_uri_size`: optional cap for inline avatar and icon data URIs. `null` leaves it unset.

Local-only secret overrides live in `config\homelab.local.json`:

```json
{
  "webui_secret_key": "replace-with-a-long-random-secret",
  "management_admin_secret": "replace-with-a-long-random-admin-secret",
  "hermes": {
    "api_server_key": "replace-with-a-long-random-hermes-api-key",
    "discord": {
      "bot_token": "replace-with-discord-bot-token",
      "allowed_users": "123456789012345678"
    },
    "photon": {
      "project_id": "",
      "project_secret": "",
      "allowed_users": "+15551234567"
    }
  },
  "ollama": {
    "models_path": "D:\\dev\\ollama"
  }
}
```

`config\homelab.local.json` is ignored by git. You can copy `config\homelab.local.example.json` as a starting point, or set `WEBUI_SECRET_KEY` and `MANAGEMENT_ADMIN_SECRET` in your shell environment instead.

If `ollama.models_path` is set and the Ollama backend is `wsl-service`, `.\scripts\wsl-bootstrap.ps1` configures the WSL `ollama` service to use the translated Linux path, such as `/mnt/d/dev/ollama`. That lets the repo keep model blobs on `D:\dev\ollama` while the runtime stays inside WSL.

## Hermes Agent

Hermes support is optional and disabled until `hermes.enabled` is set to `true`.

Before enabling it:

- Install Hermes Agent so `hermes --version` works in PowerShell.
- Run `hermes model` once and choose a custom/local endpoint that points at this machine's Ollama with a model that has at least a 64K context window.
- Run `hermes gateway setup` and select Discord plus Photon iMessage, or run `hermes photon setup --phone +15551234567` directly for Photon.
- Keep secrets in `config\homelab.local.json`; the scripts generate `state\hermes\.env` from that local file and preserve wizard-owned values such as `PHOTON_PROJECT_ID` and `PHOTON_PROJECT_SECRET`.
- Use allowlists for every channel. Hermes denies unknown users by default, and this repo treats that as the supported posture.

Recommended channel rollout:

- Discord first, using a bot token plus `DISCORD_ALLOWED_USERS` or roles.
- Photon iMessage second, using a Photon account, Node.js 18.17 or newer on PATH, and an E.164 phone number allowlist or Hermes pairing.

The manager dashboard includes an Agent page with Hermes gateway state, API reachability, platform readiness, missing local config, and recent gateway logs.

Open WebUI can keep using Ollama directly. If `hermes.api_server.enabled` is true, add `http://host.docker.internal:8642/v1` as an OpenAI-compatible connection in Open WebUI and use the local Hermes API key from `config\homelab.local.json`.

Model config lives in `config\models.json`:

```json
{
  "models": [
    "qwen3:14b",
    "qwen3:32b",
    "qwen3:8b"
  ]
}
```

## Voice And Camera Mode

For Open WebUI voice chat and camera mode:

- Use the Tailscale HTTPS URL on remote devices. Browser microphone and camera APIs usually will not work correctly over plain remote HTTP.
- Allow microphone and camera permissions in the browser.
- Use `llava:13b` as the default model for voice+camera mode in this repo.
- The startup scripts patch Open WebUI at runtime so voice/camera screenshots are normalized into Ollama-native base64 image payloads before the request reaches `llava:13b`.
- If `llava:7b` answers as if it cannot see the image, switch to `llava:13b`. It is much more reliable for screenshots and camera frames in this stack.
- `qwen3.5:9b` is the recommended fallback when you want another vision-capable option.
- Do not use `qwen3-coder` for camera mode. It is a text/code model, not the recommended multimodal target here.
- If voice/camera still says it cannot access the image after a restart, the next place to inspect is the live Open WebUI payload path rather than Ollama itself.
- If you want a cleaner picker in Open WebUI, create a Workspace model preset such as `voice-vision` backed by `llava:13b`.

## Logs

Every script run writes a timestamped log file to `logs/`. Those logs are local working files and are ignored by git.

The manager also writes runtime state, pending apply metadata, sessions, and job logs under `state/manager/`. That directory is also ignored by git.

## Docs

- [Changelog](./CHANGELOG.md)
- [Repository Map](./docs/repository-map.md)
- [Wake-on-LAN Setup Guide](./docs/wake-on-lan.md)
