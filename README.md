# Homelab AI

Homelab AI is a personal self-hosted AI workspace for coding, research, and small automation workflows.

The current stack is intentionally simple:

- Ollama runs local models on the Windows host.
- Open WebUI runs in Docker and connects to Ollama.
- OpenedAI Speech runs in Docker for local text-to-speech.
- Tailscale is the private remote access and HTTPS layer.
- PowerShell scripts keep setup, start, stop, and validation reproducible.

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

A few practical notes:

- Ollama runs on the host, not in Docker.
- Open WebUI runs in Docker on port `3000` by default, but that port is only bound to `127.0.0.1`.
- OpenedAI Speech runs in Docker on port `8000` by default, and that port is also only bound to `127.0.0.1`.
- Docker data is stored in a named volume, so Open WebUI users and chats persist across normal stop/start cycles.
- Piper voice files are stored in a Docker volume after the first setup warmup, so TTS can stay local and offline after setup.
- Open WebUI sometimes falls back to OpenAI-style voice ids such as `alloy` in the speaker UI. This repo maps those aliases back to local Piper voices so TTS still stays local.
- Local speech-to-text uses Whisper `medium` by default with language auto-detect.
- When you change `stt.model`, run `.\scripts\setup.ps1` once while internet is available so the new Whisper snapshot is cached for offline use.
- Remote access is intended to use the Tailscale HTTPS URL for this machine, such as `https://<machine>.<tailnet>.ts.net`.

## Tailscale HTTPS Prerequisites

Remote microphone and speaker-related browser APIs usually require a secure context, which means plain `http://...:3000` is not enough on other devices.

Before using the remote URL, make sure:

- Tailscale is installed on this PC and on each client device.
- Every client device is signed in to the same tailnet.
- MagicDNS is enabled for the tailnet.
- HTTPS certificates are enabled in the Tailscale admin console DNS settings.
- You run the repo PowerShell scripts from an elevated PowerShell session on Windows, because Tailscale local API access may require Administrator privileges.

When Tailscale HTTPS certificates are enabled, the machine name and tailnet DNS name become visible in certificate transparency logs. That is expected behavior for public CA-issued certificates.

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
- Pulls the local TTS image and warms the configured Piper voices once.

`.\scripts\setup.ps1 -RefreshModels`
- Re-pulls configured models even if they are already installed.

`.\scripts\start.ps1`
- Starts Ollama.
- Starts Open WebUI and the local TTS service with Docker Compose.
- Waits until both local HTTP services are reachable.
- Configures Tailscale Serve so the remote URL is HTTPS on the tailnet.

`.\scripts\stop.ps1`
- Removes the repo-managed Tailscale HTTPS mapping.
- Stops Open WebUI and the local TTS service.
- Stops Ollama.

`.\scripts\test.ps1`
- Verifies config, models, Docker Compose, Open WebUI health, local TTS health, direct TTS synthesis, Open WebUI TTS proxy synthesis, local HTTP reachability, Tailscale Serve config, and remote HTTPS reachability.

`.\scripts\status.ps1`
- Shows the current stack state in a quick human-readable form.

`.\scripts\refresh-models.ps1`
- Convenience wrapper for `setup.ps1 -RefreshModels`.

## Config

Main runtime config lives in `config\homelab.json`:

```json
{
  "hostname": "homelab-ai",
  "openwebui_port": 3000,
  "openwebui_image_tag": "v0.9.5",
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

## Docs

- [Changelog](./CHANGELOG.md)
- [Repository Map](./docs/repository-map.md)
