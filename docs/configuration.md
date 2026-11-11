# Configuration

Three files drive the stack:

| File | Tracked | Purpose |
| --- | --- | --- |
| `config/homelab.json` | yes | Ports, image tags, runtime backends, voice, Hermes and manager settings |
| `config/models.json` | yes | Ollama models the machine should have, see [models.md](./models.md) |
| `config/homelab.local.json` | **no** | Secrets and machine-specific paths |

Most settings can also be edited from the manager dashboard (Config and Models pages); the dashboard writes back to these files and tells you which action (restart, setup...) is needed to apply them.

## Runtime settings: `config/homelab.json`

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
  "hermes": { "enabled": false, "model": "hermes3:8b", "...": "see hermes.md" },
  "voice_vision_model": "llava:13b",
  "voice_vision_fallback_model": "qwen3.5:9b",
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

- `hostname` is kept for compatibility. The remote URL is discovered from Tailscale at runtime and is the source of truth.
- `openwebui_image_tag` pins the Open WebUI release. Upgrade it deliberately, then run `start.ps1` and `test.ps1`.
- `openwebui.mcp_initialize_timeout` raises the MCP handshake timeout for slow local tool servers.
- `openwebui.kb_exec_enabled` turns the built-in knowledge base filesystem tool on or off.
- `openwebui.profile_image_max_data_uri_size` caps inline avatar and icon data URIs; `null` leaves it unset.
- `tts.*` selects the local Piper voices. The default is French with an English fallback.
- `stt.model` is the Whisper model used by Open WebUI. After changing it, run `setup.ps1` once while online so the new model is cached for offline use. An empty `stt.language` means auto-detect.

## Runtime backends

The scripts support two ways to run Docker and Ollama. This repo's config uses the native Windows path.

| Setting | Values | Notes |
| --- | --- | --- |
| `runtime.container_backend` | `windows-docker` (default), `wsl-docker-engine` | Docker Desktop on Windows, or Docker Engine inside WSL |
| `runtime.ollama_backend` | `windows-process` (default), `windows-service`, `wsl-service` | Ollama on Windows, or the systemd service inside WSL |
| `runtime.wsl_distro` | e.g. `Ubuntu` | Required as soon as one WSL backend is selected |

With a WSL backend, the scripts call Docker and Ollama through `wsl.exe`, and `docker/compose.yml` maps `host.docker.internal` to the host gateway so Open WebUI can still reach Ollama. Run `.\scripts\wsl-bootstrap.ps1` once to prepare the distro.

## Local secrets: `config/homelab.local.json`

Copy `config/homelab.local.example.json` and fill in real values. The file is ignored by git.

```json
{
  "webui_secret_key": "replace-with-a-long-random-secret",
  "management_admin_secret": "replace-with-a-long-random-admin-secret",
  "hermes": {
    "api_server_key": "replace-with-a-long-random-hermes-api-key",
    "discord": { "bot_token": "...", "allowed_users": "123456789012345678" },
    "photon": { "project_id": "", "project_secret": "", "allowed_users": "+15551234567" }
  },
  "ollama": {
    "models_path": "D:\\dev\\ollama"
  }
}
```

- `webui_secret_key` signs Open WebUI sessions. Keep it stable or every user is logged out.
- `management_admin_secret` is the dashboard password. Use a long random value.
- Instead of the file, you can set the `WEBUI_SECRET_KEY` and `MANAGEMENT_ADMIN_SECRET` environment variables.
- `ollama.models_path` keeps model blobs outside the default location. With the `wsl-service` backend, `wsl-bootstrap.ps1` translates it to a WSL path such as `/mnt/d/dev/ollama`.

Generate a strong secret with a cryptographic random generator (PowerShell 7):

```powershell
[Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
```

## Local state

| Path | Content |
| --- | --- |
| `logs/` | One log file per script run |
| `state/manager/` | Manager lock, hashed sessions, sign-in throttle, pending apply actions, job history and logs |
| `state/hermes/` | Generated Hermes `.env`, `config.yaml`, logs and sessions |
| Docker volume `open-webui` | Open WebUI users, chats and settings |
| Docker volume `openedai-speech-voices` | Downloaded Piper voices |

All of it is ignored by git.
