# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

Planned as 2.0.0: optional Hermes Agent gateway, plus a cleanup to publish the repository.

### Added

- Optional Hermes Agent support with repo-managed `HERMES_HOME`, generated local Hermes `.env`/`config.yaml`, gateway lifecycle scripts, manager actions, status probes, and an Agent dashboard page.
- Photon iMessage and Discord channels for Hermes, with local-only secret examples and allowlist-first defaults.
- Hermes validation in setup and test flows, including explicit missing-secret reporting when Hermes is enabled.
- `hermes3:8b` as the default Hermes model.
- Sign-in throttling on the manager: after five failed attempts the login endpoint answers `429` with an exponential lockout capped at 15 minutes.
- GitHub Actions CI on Windows: PowerShell parsing, PSScriptAnalyzer, config JSON validation, manager UI typecheck, tests and build.
- Dependabot updates for the manager UI and GitHub Actions.
- MIT license.
- Operator docs split by topic: `docs/scripts.md`, `docs/configuration.md`, `docs/models.md`, `docs/remote-access.md`, `docs/hermes.md`.

### Changed

- `README.md` rewritten as a project overview: highlights, architecture diagram, stack, quick start, and links to the detailed docs.
- The manager dashboard moved from `scripts/manager-ui` to `manager-ui`.
- `scripts/lib/manager.ps1` split into focused modules (`manager-state`, `manager-process`, `manager-jobs`, `manager-auth`, `manager-http`, `manager-probes`, `manager-summary`, `manager-api`) with no behavior change.
- Hermes is disabled by default in `config/homelab.json`, so a fresh clone can run `setup.ps1` without the Hermes CLI or its secrets.
- `config/models.json` reduced to a default set of six models; the other models are documented as an optional catalog in `docs/models.md`.
- The OpenedAI Speech image is pinned by digest instead of `latest`.

### Fixed

- Manager UI dev dependencies updated to clear `npm audit` findings (nanoid, postcss, vitest).

## [1.0.0](https://github.com/AzaWoodyy/homelab-ai/releases/tag/1.0.0) - 2026-06-13

### Added

- A host-native remote management dashboard: PowerShell control service, authenticated JSON API, React + TypeScript SPA, and a one-job-at-a-time action runner.
- Manager lifecycle scripts for start, stop, restart, install, uninstall, status, and manager-specific validation.
- Manager config in `config/homelab.json` plus local-only `management_admin_secret` support.
- Local manager runtime state under `state/manager/` for sessions, pending apply metadata, job history, and job logs.
- Local speech: Whisper speech-to-text in Open WebUI and Piper text-to-speech through OpenedAI Speech, with voices cached for offline use.
- Voice and camera mode with `llava:13b`, including a runtime patch that normalizes camera frames into Ollama-native image payloads.
- Tailscale Serve HTTPS automation for Open WebUI and the manager.
- Sleep and shutdown actions, plus a Wake-on-LAN setup guide for a companion relay.
- A `scripts/wsl-bootstrap.ps1` flow to install and validate the Ubuntu WSL runtime, Docker Engine, Docker Compose plugin, and Ollama service.
- A boot-time scheduled task (`stack-install.ps1`, `stack-startup.ps1`) that starts the stack once Docker is ready.
- `scripts/check.ps1` developer checks.

### Changed

- `scripts/status.ps1` reports manager reachability, remote URLs, manager Tailscale Serve status, and pending apply actions.
- The runtime abstraction supports `wsl-docker-engine` and `wsl-service` backends next to the default Windows backends, routing Docker Compose and Ollama commands through `wsl.exe` when selected.
- `config/homelab.json` has an explicit `runtime` section. The default stays on Docker Desktop and the Windows Ollama process.
- `docker/compose.yml` adds `host.docker.internal:host-gateway` so Open WebUI can reach Ollama when Docker runs inside Linux.
- Open WebUI is pinned to `v0.9.6`, with repo-managed MCP timeout, opt-in KB exec, and optional profile image size cap settings exposed through config and the manager UI.

## [0.2.0](https://github.com/AzaWoodyy/homelab-ai/releases/tag/0.2.0) - 2026-06-06

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

## [0.1.0](https://github.com/AzaWoodyy/homelab-ai/releases/tag/0.1.0) - 2026-06-03

### Added

- Initial self-hosted homelab AI stack built around Ollama, Open WebUI, and Tailscale.
- Base project configuration in `config/homelab.json` and `config/models.json`.
- Initial Docker Compose definition for Open WebUI persistence and Ollama host connectivity.
- First-pass PowerShell scripts for setup, startup, and shutdown on Windows.
- Initial `README.md` and architecture documentation for the repository.
