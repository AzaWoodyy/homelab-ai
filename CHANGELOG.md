# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Optional Hermes Agent support with repo-managed `HERMES_HOME`, generated local Hermes `.env`/`config.yaml`, gateway lifecycle scripts, manager actions, status probes, and an Agent dashboard page.
- `hermes3:8b` as a configured Ollama model for the Hermes Agent local model path.
- Local-only Hermes secret examples for Discord, Photon iMessage, and the Hermes API server.
- Photon iMessage support in Hermes config, generated environment, manager UI readiness, and docs.
- Hermes validation in setup/test flows, including explicit missing-secret reporting when Hermes is enabled.
- A host-native remote management dashboard with a PowerShell control service, authenticated JSON API, static operator UI, and one-job-at-a-time action runner.
- Manager lifecycle scripts for start, stop, restart, install, uninstall, status, and manager-specific validation.
- Manager config support in `config/homelab.json` plus local-only `management_admin_secret` support.
- Local manager runtime state under `state/manager/` for sessions, pending apply metadata, job history, and job logs.
- A new `scripts/wsl-bootstrap.ps1` flow to install and validate the Ubuntu WSL runtime, Docker Engine, Docker Compose plugin, and Ollama service.

### Changed

- `scripts/status.ps1` now reports manager reachability, remote URLs, manager Tailscale Serve status, and pending apply actions.
- `README.md` and `docs/repository-map.md` now document the remote manager workflow and new scripts.
- The runtime abstraction now supports `wsl-docker-engine` and `wsl-service` backends, with Docker Compose and Ollama commands routed through `wsl.exe` when selected.
- `config/homelab.json` now includes an explicit `runtime` section defaulting this machine to Ubuntu WSL 2 for Docker and Ollama.
- `docker/compose.yml` now adds `host.docker.internal:host-gateway` so Open WebUI can still reach Ollama when Docker runs inside Linux.
- Open WebUI is now pinned to `v0.9.6`, with repo-managed MCP timeout, opt-in KB exec, and optional profile image size cap settings exposed through config and the manager UI.

## [0.2.0]

### Added

- Shared PowerShell helper layer under `scripts/lib/` for config loading, logging, Docker Compose execution, Ollama lifecycle control, and runtime checks.
- Structured script logs written to `logs/` for setup, start, stop, status, and test runs.
- New `scripts/test.ps1` end-to-end validation flow for config, Docker, Ollama, installed models, container health, and HTTP reachability.
- New `scripts/status.ps1` quick health summary for the local stack.
- New `scripts/refresh-models.ps1` wrapper for refreshing configured models.
- New `docs/repository-map.md` to document the purpose of each tracked file.
- Docker health check for the Open WebUI container.
- Local-only `config/homelab.local.json` override support for persistent Open WebUI secrets.

### Changed

- Native command execution now preserves arguments with spaces, fixing Docker health checks that use `docker inspect --format`.
- `scripts/setup.ps1` now validates Docker Compose configuration, ensures Ollama is ready, supports `-RefreshModels`, and verifies configured models after pull operations.
- `scripts/start.ps1` now waits for Open WebUI to become reachable before returning and prints both local and Tailscale URLs.
- `scripts/common.ps1` now acts as a small script loader, with focused helper implementations split into `scripts/lib/`.
- `scripts/stop.ps1` now uses the shared helper layer and gives clearer shutdown logging.
- `scripts/stop.ps1` now stops the existing Open WebUI container instead of removing it.
- `docker/compose.yml` now reads the Open WebUI port and Ollama base URL from environment variables set by the scripts.
- `docker/compose.yml` now requires a persistent `WEBUI_SECRET_KEY` and uses a pinned Open WebUI image tag.
- `config/models.json` now includes additional model presets for DeepSeek and Qwen coder workloads.
- `config/homelab.json` now pins the Open WebUI release tag in repo config.
- `README.md` and `docs/architecture.md` now describe the V2 workflow, operational scripts, persistence model, and design boundaries in more detail.

## [0.1.0](https://github.com/AzaWoodyy/homelab-ai/releases/tag/0.1.0)

### Added

- Initial self-hosted homelab AI stack built around Ollama, Open WebUI, and Tailscale.
- Base project configuration in `config/homelab.json` and `config/models.json`.
- Initial Docker Compose definition for Open WebUI persistence and Ollama host connectivity.
- First-pass PowerShell scripts for setup, startup, and shutdown on Windows.
- Initial `README.md` and architecture documentation for the repository.
