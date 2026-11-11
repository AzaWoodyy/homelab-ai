# Models

`config/models.json` lists the Ollama models this machine should have. `setup.ps1` pulls the missing ones, `test.ps1` checks they are installed, and the dashboard Models page edits the list.

Removing a model from the file does not delete it from disk. Only removing it from the dashboard Models page runs `ollama rm`.

## Default set

The default list is kept small so a fresh setup finishes in a reasonable time and fits on a typical SSD.

| Model | Role |
| --- | --- |
| `qwen3:8b` | Fast everyday chat |
| `qwen3:14b` | Better quality chat when the GPU has room |
| `qwen3-coder` | Coding assistant |
| `llava:13b` | Voice and camera mode (`voice_vision_model`) |
| `qwen3.5:9b` | Vision fallback (`voice_vision_fallback_model`) |
| `hermes3:8b` | Hermes Agent model (`hermes.model`) |

The last three are referenced by `config/homelab.json`: keep them in the list, or update the config at the same time.

## Optional catalog

Models that were tried on this stack and can be added to `config/models.json` when needed:

| Model | Use |
| --- | --- |
| `qwen3:32b`, `qwen3.5:27b`, `qwen3.5:35b`, `qwen3.6:27b` | Larger general-purpose models |
| `deepseek-r1:32b` | Reasoning |
| `gpt-oss:20b`, `nemotron3:33b`, `gemma4:12b`, `gemma4:26b` | Alternative general-purpose models |
| `llava:7b`, `llava:34b` | Smaller or larger vision models |
| `translategemma:4b`, `translategemma:12b` | Translation |

Check the size on the [Ollama library](https://ollama.com/library) before adding the larger ones: 30B-class models need roughly 20 GB of disk each and a GPU with matching VRAM to run at a usable speed.

## Voice and camera notes

- `llava:13b` is the most reliable choice for screenshots and camera frames. `llava:7b` often answers as if it could not see the image.
- `qwen3.5:9b` is the recommended second vision option.
- Do not use `qwen3-coder` for camera mode: it is a text and code model.
- In Open WebUI, a Workspace model preset such as `voice-vision` backed by `llava:13b` keeps the model picker clean.
