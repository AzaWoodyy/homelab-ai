# Architecture V2

## Goal

Run a private, reproducible AI workspace on a Windows gaming PC with as little infrastructure as possible.

This version focuses on one machine, one web UI, local models, and private remote access through Tailscale.

## Main Flow

```text
Laptop / Phone
      |
  Tailscale
      |
Gaming PC (Windows 11)
      |
Open WebUI (Docker)
      |
Ollama (Host)
      |
Qwen3 models
```

## Runtime Pieces

`Ollama`
- Runs directly on the Windows host.
- Owns the local model runtime and model storage.

`Open WebUI`
- Runs in Docker through `docker/compose.yml`.
- Exposes the UI on port `3000` by default.
- Connects back to host Ollama through `host.docker.internal:11434`.

`Tailscale`
- Provides private remote access without opening public ports.
- Lets other devices reach the gaming PC over the tailnet.
- Optional MagicDNS support makes `http://homelab-ai:3000` nicer than using a raw Tailscale IP.

## Control Layer

The `scripts/` folder is the control plane for the repo:

- `setup.ps1` installs or updates configured models.
- `start.ps1` starts Ollama and Open WebUI.
- `stop.ps1` stops Open WebUI and Ollama.
- `test.ps1` validates the full local stack.
- `status.ps1` gives a quick health snapshot.
- `update.ps1` is a convenience wrapper for model refreshes.
- `common.ps1` holds shared script logic.

## Data Persistence

Open WebUI data is stored in a named Docker volume.

That means:

- normal `start` and `stop` cycles keep users, chats, and settings
- deleting the container does not delete the data volume
- `docker compose down -v` would remove the Open WebUI data

Ollama models are managed separately by Ollama on the host.

## V2 Improvements

Compared with V1, V2 adds:

- shared PowerShell helpers
- structured logging to `logs/`
- config-driven port and hostname handling
- model validation
- `setup.ps1 -Update`
- Docker health checks
- a real `test.ps1` for stack validation

## Design Boundaries

Things intentionally not included yet:

- Kubernetes
- public reverse proxy
- public domain exposure
- Keycloak or Authentik
- agent orchestration beyond early placeholders

The idea is to keep the stack understandable by one person and easy to pause when the PC is needed for gaming.
