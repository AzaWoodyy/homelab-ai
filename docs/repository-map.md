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
- Ignores local manager runtime state under `state/`.

## config/

`config/homelab.json`
- Main runtime settings for the local stack.
- Defines the hostname, the Open WebUI and manager port settings, the pinned Open WebUI image tag, a few repo-managed advanced Open WebUI settings, the preferred voice/camera models, local TTS defaults, and local Whisper STT defaults.

`config/homelab.local.example.json`
- Example local-only override file for secrets.
- Shows where to place `WEBUI_SECRET_KEY` and `MANAGEMENT_ADMIN_SECRET` without committing them.

`config/models.json`
- List of Ollama models the repo expects to exist locally.
- `setup.ps1` reads this file and keeps the machine aligned with it.

## docker/

`docker/compose.yml`
- Docker Compose definition for Open WebUI and the local TTS service.
- Maps the host loopback ports, sets the Ollama and TTS connection URLs, and defines the container health checks.

`docker/openedai-speech/voice_to_speaker.yaml`
- Repo-managed Piper voice mapping for the local TTS service.
- Keeps the default French and English voices reproducible.
- Also maps OpenAI-style voice aliases such as `alloy` back to local Piper voices for the Open WebUI speaker UI.

## docs/

`docs/repository-map.md`
- This file.
- Useful when you want the "what is each file for" view.

`docs/wake-on-lan.md`
- Contributor guide for reliable Wake-on-LAN setup on the Windows gaming PC.
- Covers firmware prerequisites, Windows and NIC settings, local validation, and the Tailscale relay topology.

## scripts/

`scripts/common.ps1`
- Shared PowerShell bootstrap file.
- Sets repo-level script state and loads the focused helpers in `scripts/lib/`.

`scripts/lib/*.ps1`
- Focused PowerShell helper files grouped by responsibility.
- Covers shared utilities, logging, native command execution, config loading, dependency discovery, model validation, Ollama control, Docker Compose calls, Open WebUI config synchronization and runtime patching, HTTP health checks, TTS validation, and Tailscale HTTPS automation.

`scripts/check.ps1`
- Lightweight developer check script.
- Parses tracked PowerShell scripts, validates config JSON files, and runs the manager UI check.

`scripts/setup.ps1`
- Validates the local prerequisites.
- Ensures configured models exist locally.
- Pulls and warms the local TTS service and its configured Piper voices.
- Supports `-RefreshModels` to force model refreshes.

`scripts/start.ps1`
- Starts Ollama.
- Starts Open WebUI and local TTS.
- Waits until both services are actually reachable before returning.

`scripts/stop.ps1`
- Stops Open WebUI and local TTS.
- Keeps the existing container definition so the next start can reuse it.
- Stops Ollama afterward to free resources.

`scripts/test.ps1`
- End-to-end validation script.
- Checks config, Docker, Ollama, installed models, container health, direct TTS synthesis, Open WebUI TTS proxy synthesis, and HTTP reachability.

`scripts/status.ps1`
- Short operational summary for the current machine state.
- Useful when you want a quick answer instead of running full validation.

`scripts/refresh-models.ps1`
- Small wrapper around `setup.ps1 -RefreshModels`.
- Exists mainly to make "refresh configured models" obvious.

`scripts/manager-service.ps1`
- Host-native local web service for the remote management dashboard.
- Serves the static dashboard UI and authenticated JSON APIs on the manager port.

`scripts/manager-start.ps1`, `scripts/manager-stop.ps1`, `scripts/manager-restart.ps1`
- Lifecycle helpers for the manager service.
- Keep manager control independent from the main stack lifecycle.

`scripts/manager-install.ps1`, `scripts/manager-uninstall.ps1`
- User-logon scheduled-task helpers for making the manager come back automatically after reboot once the Windows user signs in.

`scripts/manager-status.ps1`, `scripts/manager-test.ps1`
- Quick diagnostics for the manager control surface itself.

`scripts/manager-ui/*`
- React and TypeScript source for the manager dashboard.
- `npm.cmd run build` writes the static SPA to `scripts/manager-ui/dist`, which is served by the manager service.
- Contains the login page, operator console, editing forms, and live job UI.

## logs/

`logs/*.log`
- Timestamped output from script runs.
- Helpful for debugging failed starts, setup issues, or health checks.
- Ignored by git because they are machine-local working data.

## state/

`state/manager/*`
- Local-only manager runtime state such as the lock file, sessions, pending apply metadata, and job logs.
- Ignored by git because it is machine-local operational state.
