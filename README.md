# Homelab AI

Homelab AI is a personal self-hosted AI workspace for coding, research, and small automation workflows.

The current stack is intentionally simple:

- Ollama runs local models on the Windows host.
- Open WebUI runs in Docker and connects to Ollama.
- Tailscale is the private remote access layer.
- PowerShell scripts keep setup, start, stop, and validation reproducible.

## What This Repo Tries To Do

- Stay private by default.
- Be easy to understand and easy to stop.
- Keep local inference on one powerful PC.
- Let laptops and phones reach the UI through Tailscale.
- Avoid heavyweight infrastructure until it is clearly needed.

## How It Works

The main path is:

`Laptop or phone -> Tailscale -> Gaming PC -> Open WebUI -> Ollama -> Local model`

A few practical notes:

- Ollama runs on the host, not in Docker.
- Open WebUI runs in Docker on port `3000` by default.
- Docker data is stored in a named volume, so Open WebUI users and chats persist across normal stop/start cycles.
- `http://homelab-ai:3000` works from another device only when Tailscale name resolution is set up on the tailnet.

## Quick Start

Initial setup:

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

Stop the stack:

```powershell
.\scripts\stop.ps1
```

## Script Guide

`.\scripts\setup.ps1`
- Validates Docker and Ollama.
- Reads configured models from `config\models.json`.
- Pulls only missing models.

`.\scripts\setup.ps1 -Update`
- Re-pulls configured models even if they are already installed.

`.\scripts\start.ps1`
- Starts Ollama.
- Starts Open WebUI with Docker Compose.
- Waits until the UI is reachable.

`.\scripts\stop.ps1`
- Stops Open WebUI.
- Stops Ollama.

`.\scripts\test.ps1`
- Verifies config, models, Docker Compose, Open WebUI health, and HTTP reachability.

`.\scripts\status.ps1`
- Shows the current stack state in a quick human-readable form.

`.\scripts\update.ps1`
- Convenience wrapper for `setup.ps1 -Update`.

## Config

Main runtime config lives in `config\homelab.json`:

```json
{
  "hostname": "homelab-ai",
  "openwebui_port": 3000,
  "openwebui_image_tag": "v0.9.5"
}
```

Local-only secret overrides live in `config\homelab.local.json`:

```json
{
  "webui_secret_key": "replace-with-a-long-random-secret"
}
```

`config\homelab.local.json` is ignored by git. You can copy `config\homelab.local.example.json` as a starting point, or set `WEBUI_SECRET_KEY` in your shell environment instead.

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

## Logs

Every script run writes a timestamped log file to `logs/`. Those logs are local working files and are ignored by git.

## Docs

- [Changelog](./CHANGELOG.md)
- [Repository Map](./docs/repository-map.md)
