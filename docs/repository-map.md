# Repository Map

This document gives the short version of what each file is for, so a new person can scan the repo without guessing.

## Root

`README.md`
- Project entry point.
- Explains the purpose of the repo, the main workflow, and the most important commands.

`CHANGELOG.md`
- Release notes for the repo.
- Summarizes what changed between published versions.

`.gitignore`
- Ignores local-only working files such as script logs.
- Ignores the local secret override file for Open WebUI.

## config/

`config/homelab.json`
- Main runtime settings for the local stack.
- Defines the hostname, the Open WebUI port, and the pinned Open WebUI image tag.

`config/homelab.local.example.json`
- Example local-only override file for secrets.
- Shows where to place `WEBUI_SECRET_KEY` without committing it.

`config/models.json`
- List of Ollama models the repo expects to exist locally.
- `setup.ps1` reads this file and keeps the machine aligned with it.

## docker/

`docker/compose.yml`
- Docker Compose definition for Open WebUI.
- Maps the host port, sets the Ollama connection URL, and defines the health check.

## docs/

`docs/architecture.md`
- High-level explanation of the V2 system design.
- Useful when you want the "why this looks like this" view.

`docs/repository-map.md`
- This file.
- Useful when you want the "what is each file for" view.

## scripts/

`scripts/common.ps1`
- Shared PowerShell helper functions.
- Handles logging, config loading, dependency checks, Ollama control, Docker Compose calls, secret injection, and health validation.

`scripts/setup.ps1`
- Validates the local prerequisites.
- Ensures configured models exist locally.
- Supports `-Update` to force model refreshes.

`scripts/start.ps1`
- Starts Ollama.
- Starts Open WebUI.
- Waits until the UI is actually reachable before returning.

`scripts/stop.ps1`
- Stops Open WebUI.
- Keeps the existing container definition so the next start can reuse it.
- Stops Ollama afterward to free resources.

`scripts/test.ps1`
- End-to-end validation script.
- Checks config, Docker, Ollama, installed models, container health, and HTTP reachability.

`scripts/status.ps1`
- Short operational summary for the current machine state.
- Useful when you want a quick answer instead of running full validation.

`scripts/update.ps1`
- Small wrapper around `setup.ps1 -Update`.
- Exists mainly to make "refresh configured models" obvious.

## logs/

`logs/*.log`
- Timestamped output from script runs.
- Helpful for debugging failed starts, setup issues, or health checks.
- Ignored by git because they are machine-local working data.
