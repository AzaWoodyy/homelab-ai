# Remote access, voice and camera mode

## How remote access works

No port is opened on the router. Every service binds to `127.0.0.1`, and Tailscale Serve publishes two of them over HTTPS on the tailnet:

| URL | Target |
| --- | --- |
| `https://<machine>.<tailnet>.ts.net` | Open WebUI (`127.0.0.1:3000`) |
| `https://<machine>.<tailnet>.ts.net:8443` | Manager dashboard (`127.0.0.1:3081`) |

`start.ps1` and `manager-start.ps1` create these mappings, `stop.ps1` and `manager-stop.ps1` remove them.

## Tailscale prerequisites

Browsers only allow the microphone and camera in a secure context, so plain `http://<ip>:3000` from another device is not enough. Before using the remote URL:

- Install Tailscale on the PC and on every client, all signed in to the same tailnet.
- Enable MagicDNS for the tailnet.
- Enable HTTPS certificates in the Tailscale admin console (DNS settings).
- Run the repo scripts from an elevated PowerShell session: the Tailscale local API may require Administrator rights.

With HTTPS certificates enabled, the machine name and tailnet DNS name appear in public certificate transparency logs. That is expected for CA-issued certificates; pick a machine name you are fine publishing.

## Manager security model

- The dashboard is only reachable on loopback or through the tailnet.
- One admin secret (`management_admin_secret`), compared in constant time.
- Sessions are random tokens stored hashed on disk, sent as `HttpOnly; SameSite=Strict` cookies, marked `Secure` over HTTPS, and expire after 24 hours.
- Every state-changing request needs the session's CSRF token.
- After five failed sign-ins, the login endpoint answers `429` with an exponential lockout (30 s, doubling, capped at 15 minutes). A successful sign-in resets it.
- Actions run one at a time in a separate job process, with logs visible in the dashboard.

## Voice mode

- Speech-to-text: Whisper inside Open WebUI (`stt.model`, `medium` by default, language auto-detect).
- Text-to-speech: Piper voices served by OpenedAI Speech. Voices are downloaded once by `setup.ps1` and stored in a Docker volume, so speech works offline afterwards.
- Open WebUI sometimes falls back to OpenAI voice ids such as `alloy`. `docker/openedai-speech/voice_to_speaker.yaml` maps them back to local Piper voices, so nothing is sent to OpenAI.

## Camera mode

- Allow microphone and camera in the browser, using the HTTPS URL.
- Use `llava:13b` (see [models.md](./models.md)).
- The start scripts patch Open WebUI at runtime so camera frames and screenshots are converted to Ollama-native base64 image payloads before they reach the model.
- If the model still says it cannot see the image after a restart, inspect the live Open WebUI request payload first; Ollama is rarely the cause.

## Waking the PC remotely

Sleep and shutdown are available from the dashboard. Waking the PC back up is handled by a separate Wake-on-LAN relay on an always-on device: `phone -> Tailscale -> wake relay -> magic packet -> PC`. See [wake-on-lan.md](./wake-on-lan.md).
