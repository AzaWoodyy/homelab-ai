# Hermes Agent

[Hermes Agent](https://github.com/NousResearch/hermes-agent) is an optional messaging gateway. It lets you talk to the local models from Discord or iMessage, and it exposes an OpenAI-compatible API that Open WebUI can use as an extra connection.

It is disabled by default. While `hermes.enabled` is `false` in `config/homelab.json`, setup, start, stop and test skip it entirely. Complete the setup below before turning it on: with Hermes enabled, `setup.ps1` stops on a missing CLI or missing secrets.

## Request path

`Discord or iMessage -> Hermes gateway -> Hermes Agent -> Ollama (hermes3:8b) + configured tools`

## Configuration

```json
"hermes": {
  "enabled": false,
  "home": "state\\hermes",
  "model": "hermes3:8b",
  "gateway": { "enabled": true },
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
}
```

- `home` becomes `HERMES_HOME`. The scripts generate `.env` and `config.yaml` there from your local secrets, and keep values owned by the Hermes wizards such as `PHOTON_PROJECT_ID` and `PHOTON_PROJECT_SECRET`.
- The gateway runs as a hidden host-native user process.
- The API server listens on `127.0.0.1:8642` only.

Secrets go in `config/homelab.local.json` (see [configuration.md](./configuration.md)): `hermes.api_server_key`, `hermes.discord.bot_token` and `allowed_users`, `hermes.photon.*`.

## Setup

1. Install Hermes Agent so `hermes --version` works in PowerShell.
2. Run `hermes model` once and choose a custom/local endpoint pointing at this machine's Ollama, with a model that has at least a 64K context window.
3. Run `hermes gateway setup` and select Discord and/or Photon iMessage, or run `hermes photon setup --phone <your E.164 number>` for Photon only.
4. Fill the secrets in `config/homelab.local.json`.
5. Set `hermes.enabled` to `true` in `config/homelab.json`, run `.\scripts\setup.ps1`, then start with `.\scripts\start.ps1` (whole stack) or `.\scripts\hermes-start.ps1` (gateway only).

## Channels

Use an allowlist on every channel. Hermes denies unknown users by default, and this repo treats that as the supported posture.

- **Discord first:** a bot token plus `allowed_users` (or roles). Mentions are required by default.
- **Photon iMessage second:** a Photon account, Node.js 18.17 or newer on `PATH`, and an E.164 phone number allowlist or Hermes pairing.

## Open WebUI connection

Open WebUI keeps talking to Ollama directly. To also chat with the agent from Open WebUI, add an OpenAI-compatible connection:

- URL: `http://host.docker.internal:8642/v1`
- API key: `hermes.api_server_key` from `config/homelab.local.json`

## Dashboard

The manager's Agent page shows the gateway state, API reachability, per-platform readiness, missing local config and the latest gateway logs, with start, stop and restart actions.
