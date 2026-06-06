# Changelog

All notable changes to this project will be documented in this file.

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
