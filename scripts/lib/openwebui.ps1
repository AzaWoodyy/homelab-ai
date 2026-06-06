function Invoke-OpenWebUiPythonRaw {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$PythonCode
    )

    return Invoke-NativeCommand -FilePath "docker" -Arguments @(
        "exec",
        $Config.openwebui_container_name,
        "python",
        "-c",
        $PythonCode
    )
}

function Invoke-OpenWebUiPython {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$PythonCode
    )

    $result = Invoke-OpenWebUiPythonRaw -Config $Config -PythonCode $PythonCode

    if ($result.ExitCode -ne 0) {
        $message = ($result.StdErr + [Environment]::NewLine + $result.StdOut).Trim()
        throw $message
    }

    return $result.StdOut
}

function Sync-OpenWebUiPersistedConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $voicePromptTemplate = "When voice or camera mode is active, respond briefly and conversationally. If an image, screenshot, or camera frame is attached, inspect that visual input directly before answering. Only say you cannot access the image when no visual input was actually provided."
    $voicePromptTemplateJson = ($voicePromptTemplate | ConvertTo-Json -Compress)

    $pythonCode = @"
import json
import sqlite3

db_path = '/app/backend/data/webui.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute('select id, data from config order by id desc limit 1')
row = cur.fetchone()
if row is None:
    raise RuntimeError('No Open WebUI config row found')

config = json.loads(row[1])
audio = config.setdefault('audio', {})
tts = audio.setdefault('tts', {})
stt = audio.setdefault('stt', {})
task = config.setdefault('task', {})
voice = task.setdefault('voice', {})
prompt = voice.setdefault('prompt', {})

tts.setdefault('openai', {})
tts['engine'] = 'openai'
tts['model'] = '$($Config.tts_model)'
tts['voice'] = '$($Config.tts_default_voice)'
tts['api_key'] = 'local-tts'
tts['openai']['api_base_url'] = 'http://$($Config.tts_container_name):8000/v1'
tts['openai']['api_key'] = 'local-tts'
tts['split_on'] = 'punctuation'

stt['engine'] = ''
stt['model'] = ''
stt['whisper_model'] = '$($Config.stt_model)'
stt['whisper_language'] = '$($Config.stt_language)'

prompt['enable'] = True
voice['prompt_template'] = $voicePromptTemplateJson

cur.execute('update config set data = ?, updated_at = CURRENT_TIMESTAMP where id = ?', (json.dumps(config), row[0]))
conn.commit()
conn.close()
print('openwebui-config-synced')
"@

    return (Invoke-OpenWebUiPython -Config $Config -PythonCode $pythonCode).Trim()
}

function Ensure-OpenWebUiPersistedConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $result = Sync-OpenWebUiPersistedConfig -Config $Config

    if ($result -notmatch "openwebui-config-synced") {
        throw "Unexpected Open WebUI config sync result: $result"
    }
}

function Ensure-OpenWebUiRuntimePatch {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $pythonCode = @"
from pathlib import Path
import re

main_path = Path('/app/backend/open_webui/main.py')
main_text = main_path.read_text(encoding='utf-8')
main_patch_marker = "HOMELAB_VOICE_VISION_PATCH_VERSION = '2026-06-06-broadened'"

main_helper = '''

HOMELAB_VOICE_VISION_PATCH_VERSION = '2026-06-06-broadened'

def merge_attached_image_files_into_messages(form_data: dict) -> dict:
    def collect_from_files(files):
        urls = []

        if not isinstance(files, list):
            return urls

        for file_item in files:
            if not isinstance(file_item, dict):
                continue

            if file_item.get('type') != 'image':
                continue

            url = file_item.get('url') or file_item.get('src')
            if isinstance(url, str) and url:
                urls.append(url)

        return urls

    image_urls = []
    image_urls.extend(collect_from_files(form_data.get('files')))

    metadata = form_data.get('metadata')
    if isinstance(metadata, dict):
        image_urls.extend(collect_from_files(metadata.get('files')))

    for message_key in ('user_message', 'parent_message'):
        message = form_data.get(message_key)
        if isinstance(message, dict):
            image_urls.extend(collect_from_files(message.get('files')))

    if not image_urls:
        return form_data

    messages = form_data.get('messages')
    if not isinstance(messages, list):
        return form_data

    deduped_urls = []
    seen_urls = set()
    for url in image_urls:
        if url not in seen_urls:
            deduped_urls.append(url)
            seen_urls.add(url)

    for message in reversed(messages):
        if not isinstance(message, dict) or message.get('role') != 'user':
            continue

        content = message.get('content')
        existing_urls = set()

        if isinstance(content, list):
            for item in content:
                if not isinstance(item, dict):
                    continue

                if item.get('type') == 'image_url':
                    url = item.get('image_url', {}).get('url')
                    if url:
                        existing_urls.add(url)

            for url in deduped_urls:
                if url not in existing_urls:
                    content.append({'type': 'image_url', 'image_url': {'url': url}})
        else:
            text_content = content if isinstance(content, str) else ''
            message['content'] = []

            if text_content:
                message['content'].append({'type': 'text', 'text': text_content})

            for url in deduped_urls:
                message['content'].append({'type': 'image_url', 'image_url': {'url': url}})

        break

    return form_data
'''

main_call_old = """    if not request.app.state.MODELS:
        await get_all_models(request, user=user)

    model_id = form_data.get('model', None)
"""
main_call_new = """    if not request.app.state.MODELS:
        await get_all_models(request, user=user)

    form_data = merge_attached_image_files_into_messages(form_data)

    model_id = form_data.get('model', None)
"""

chat_path = Path('/app/backend/open_webui/utils/chat.py')
chat_text = chat_path.read_text(encoding='utf-8')
chat_patch_marker = "HOMELAB_OLLAMA_NATIVE_IMAGES_PATCH_VERSION = '2026-06-06-ollama-native-images'"

chat_helper = '''

HOMELAB_OLLAMA_NATIVE_IMAGES_PATCH_VERSION = '2026-06-06-ollama-native-images'

async def apply_homelab_ollama_native_images(openai_form_data: dict, ollama_form_data: dict) -> dict:
    from open_webui.utils.files import get_image_base64_from_url
    import re

    file_url_pattern = re.compile(r"/api/v1/files/([^/]+)(?:/content(?:/[^/?#]+)?)?(?:[?#].*)?$")

    def collect_from_files(files):
        refs = []

        if not isinstance(files, list):
            return refs

        for file_item in files:
            if not isinstance(file_item, dict):
                continue

            if file_item.get('type') != 'image':
                continue

            ref = file_item.get('url') or file_item.get('src') or file_item.get('id')
            if isinstance(ref, str) and ref:
                refs.append(ref)

        return refs

    def normalize_file_reference(ref):
        if not isinstance(ref, str) or not ref:
            return None

        if ref.startswith('data:image/'):
            return ref

        match = file_url_pattern.search(ref)
        if match:
            return match.group(1)

        return ref

    def collect_from_content(content):
        refs = []

        if not isinstance(content, list):
            return refs

        for item in content:
            if not isinstance(item, dict):
                continue

            if item.get('type') != 'image_url':
                continue

            ref = item.get('image_url', {}).get('url')
            if isinstance(ref, str) and ref:
                refs.append(ref)

        return refs

    def append_image_value(value, output, seen):
        if not isinstance(value, str) or not value:
            return

        if value.startswith('data:image/'):
            value = value.split(',', 1)[-1]

        if value and value not in seen:
            seen.add(value)
            output.append(value)

    image_refs = []
    image_refs.extend(collect_from_files(openai_form_data.get('files')))

    metadata = openai_form_data.get('metadata')
    if isinstance(metadata, dict):
        image_refs.extend(collect_from_files(metadata.get('files')))

    for message_key in ('user_message', 'parent_message'):
        message = openai_form_data.get(message_key)
        if isinstance(message, dict):
            image_refs.extend(collect_from_files(message.get('files')))

    openai_messages = openai_form_data.get('messages')
    if isinstance(openai_messages, list):
        for message in reversed(openai_messages):
            if not isinstance(message, dict) or message.get('role') != 'user':
                continue

            image_refs.extend(collect_from_files(message.get('files')))
            image_refs.extend(collect_from_content(message.get('content')))
            break

    ollama_messages = ollama_form_data.get('messages')
    if not isinstance(ollama_messages, list):
        return ollama_form_data

    normalized_images = []
    seen_images = set()

    for message in reversed(ollama_messages):
        if not isinstance(message, dict) or message.get('role') != 'user':
            continue

        existing_images = message.get('images')
        if isinstance(existing_images, list):
            for image_value in existing_images:
                append_image_value(image_value, normalized_images, seen_images)
        break

    for ref in image_refs:
        normalized_ref = normalize_file_reference(ref)
        if not normalized_ref:
            continue

        if normalized_ref.startswith('data:image/'):
            append_image_value(normalized_ref, normalized_images, seen_images)
            continue

        image_base64 = await get_image_base64_from_url(normalized_ref)
        if image_base64:
            append_image_value(image_base64, normalized_images, seen_images)

    if not normalized_images:
        return ollama_form_data

    for message in reversed(ollama_messages):
        if not isinstance(message, dict) or message.get('role') != 'user':
            continue

        if message.get('content') is None:
            message['content'] = ''
        elif not isinstance(message.get('content'), str):
            message['content'] = str(message.get('content'))

        message['images'] = normalized_images
        break

    return ollama_form_data
'''

chat_call_old = """        if model.get('owned_by') == 'ollama':
            # Using /ollama/api/chat endpoint
            form_data = convert_payload_openai_to_ollama(form_data)
            response = await generate_ollama_chat_completion(
"""
chat_call_new = """        if model.get('owned_by') == 'ollama':
            # Using /ollama/api/chat endpoint
            openai_form_data = form_data
            form_data = convert_payload_openai_to_ollama(form_data)
            form_data = await apply_homelab_ollama_native_images(openai_form_data, form_data)
            response = await generate_ollama_chat_completion(
"""

changes = []

if main_patch_marker not in main_text:
    anchor = "@app.post('/api/chat/completions')"
    if anchor not in main_text:
        raise RuntimeError('Open WebUI chat completion anchor not found')

    old_helper_pattern = r"\n(?:HOMELAB_VOICE_VISION_PATCH_VERSION = '.*?'\n\n)?def merge_attached_image_files_into_messages\(form_data: dict\) -> dict:\n.*?(?=\n@app\.post\('/api/chat/completions'\))"
    main_text, count = re.subn(old_helper_pattern, main_helper, main_text, count=1, flags=re.S)
    if count == 0:
        main_text = main_text.replace(anchor, main_helper + "\n" + anchor, 1)
    changes.append('main-helper')

if main_call_new not in main_text:
    if main_call_old not in main_text:
        raise RuntimeError('Open WebUI chat completion injection point not found')
    main_text = main_text.replace(main_call_old, main_call_new, 1)
    changes.append('main-call')

if changes:
    main_path.write_text(main_text, encoding='utf-8')

chat_changes = []

if chat_patch_marker not in chat_text:
    anchor = "async def generate_chat_completion("
    if anchor not in chat_text:
        raise RuntimeError('Open WebUI chat utility anchor not found')

    old_helper_pattern = r"\n(?:HOMELAB_OLLAMA_NATIVE_IMAGES_PATCH_VERSION = '.*?'\n\n)?async def apply_homelab_ollama_native_images\(openai_form_data: dict, ollama_form_data: dict\) -> dict:\n.*?(?=\nasync def generate_chat_completion\()"
    chat_text, count = re.subn(old_helper_pattern, chat_helper, chat_text, count=1, flags=re.S)
    if count == 0:
        chat_text = chat_text.replace(anchor, chat_helper + "\n" + anchor, 1)
    chat_changes.append('chat-helper')

if chat_call_new not in chat_text:
    if chat_call_old not in chat_text:
        raise RuntimeError('Open WebUI Ollama conversion injection point not found')
    chat_text = chat_text.replace(chat_call_old, chat_call_new, 1)
    chat_changes.append('chat-call')

if chat_changes:
    chat_path.write_text(chat_text, encoding='utf-8')

if chat_changes:
    print('openwebui-runtime-patch-ollama-native-images-applied')
elif changes:
    print('openwebui-runtime-patch-broadened-applied')
else:
    print('openwebui-runtime-patch-ollama-native-images-already-present')
"@

    $result = (Invoke-OpenWebUiPython -Config $Config -PythonCode $pythonCode).Trim()

    if ($result -notin @(
        "openwebui-runtime-patch-ollama-native-images-applied",
        "openwebui-runtime-patch-ollama-native-images-already-present",
        "openwebui-runtime-patch-broadened-applied"
    )) {
        throw "Unexpected Open WebUI runtime patch result: $result"
    }
}

function Get-OpenWebUiWhisperCacheState {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [switch]$AllowDownload
    )

    $allowDownloadLiteral = if ($AllowDownload) { "True" } else { "False" }
    $pythonCode = @"
import json
import os
from pathlib import Path

from faster_whisper import WhisperModel
from open_webui.config import WHISPER_COMPUTE_TYPE, WHISPER_MODEL_DIR

model_name = '$($Config.stt_model)'
allow_download = $allowDownloadLiteral
download_root = WHISPER_MODEL_DIR
result = {
    'model': model_name,
    'download_root': download_root,
    'cached': False,
    'downloaded': False,
    'local_error': '',
    'download_error': '',
    'cache_entries': [],
}

def build(local_files_only: bool):
    return WhisperModel(
        model_size_or_path=model_name,
        device='cpu',
        compute_type=WHISPER_COMPUTE_TYPE,
        download_root=download_root,
        local_files_only=local_files_only,
    )

try:
    build(True)
    result['cached'] = True
except Exception as exc:
    result['local_error'] = str(exc)

if not result['cached'] and allow_download:
    os.environ['HF_HUB_OFFLINE'] = '0'
    try:
        build(False)
        result['cached'] = True
        result['downloaded'] = True
    except Exception as exc:
        result['download_error'] = str(exc)

cache_root = Path(download_root)
if cache_root.exists():
    entries = []
    for path in sorted(cache_root.iterdir()):
        entries.append(path.name + ('/' if path.is_dir() else ''))
    result['cache_entries'] = entries

print('HOMELAB_JSON=' + json.dumps(result))
raise SystemExit(0 if result['cached'] else 2)
"@

    $rawResult = Invoke-OpenWebUiPythonRaw -Config $Config -PythonCode $pythonCode
    $combinedOutput = ($rawResult.StdOut + [Environment]::NewLine + $rawResult.StdErr).Trim()
    $match = [regex]::Match($combinedOutput, "HOMELAB_JSON=(\{.*\})", [System.Text.RegularExpressions.RegexOptions]::Singleline)

    if (-not $match.Success) {
        if ($rawResult.ExitCode -ne 0) {
            throw (($rawResult.StdErr + [Environment]::NewLine + $rawResult.StdOut).Trim())
        }

        throw "Could not read Open WebUI Whisper cache state."
    }

    $state = $match.Groups[1].Value | ConvertFrom-Json
    $state | Add-Member -NotePropertyName ExitCode -NotePropertyValue $rawResult.ExitCode

    return $state
}

function Ensure-OpenWebUiWhisperModelCached {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $state = Get-OpenWebUiWhisperCacheState -Config $Config -AllowDownload

    if (-not $state.cached) {
        $reason = if (-not [string]::IsNullOrWhiteSpace([string]$state.download_error)) {
            [string]$state.download_error
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$state.local_error)) {
            [string]$state.local_error
        }
        else {
            "Unknown Whisper cache failure."
        }

        throw "Whisper model '$($Config.stt_model)' could not be cached locally. $reason"
    }

    return $state
}

function Assert-OpenWebUiWhisperModelCached {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $state = Get-OpenWebUiWhisperCacheState -Config $Config

    if (-not $state.cached) {
        $reason = if (-not [string]::IsNullOrWhiteSpace([string]$state.local_error)) {
            [string]$state.local_error
        }
        else {
            "No cached Whisper snapshot was found."
        }

        throw "Whisper model '$($Config.stt_model)' is not cached locally for offline use. Run .\\scripts\\setup.ps1 once with internet access. $reason"
    }

    return $state
}

function Get-OpenWebUiRuntimePatchState {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $pythonCode = @"
from pathlib import Path

main_text = Path('/app/backend/open_webui/main.py').read_text(encoding='utf-8')
chat_text = Path('/app/backend/open_webui/utils/chat.py').read_text(encoding='utf-8')

native_required = [
    "HOMELAB_OLLAMA_NATIVE_IMAGES_PATCH_VERSION = '2026-06-06-ollama-native-images'",
    'async def apply_homelab_ollama_native_images(',
    "openai_form_data = form_data",
    'form_data = await apply_homelab_ollama_native_images(openai_form_data, form_data)',
    "message['images'] = normalized_images"
]

broadened_required = [
    "HOMELAB_VOICE_VISION_PATCH_VERSION = '2026-06-06-broadened'",
    'def merge_attached_image_files_into_messages(',
    'form_data = merge_attached_image_files_into_messages(form_data)',
    "metadata = form_data.get('metadata')",
    "for message_key in ('user_message', 'parent_message')"
]

if all(item in chat_text for item in native_required):
    print('ollama-native-images')
elif all(item in main_text for item in broadened_required):
    print('broadened')
else:
    print('missing')
"@

    return (Invoke-OpenWebUiPython -Config $Config -PythonCode $pythonCode).Trim()
}

function Get-OpenWebUiOllamaNativeImageReplayResult {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $pythonCode = @"
import asyncio
import base64
import json
import struct
import zlib

from open_webui.utils.chat import apply_homelab_ollama_native_images
from open_webui.utils.payload import convert_payload_openai_to_ollama

def png_chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack('!I', len(data))
        + tag
        + data
        + struct.pack('!I', zlib.crc32(tag + data) & 0xFFFFFFFF)
    )

def build_png_base64(width: int = 128, height: int = 128) -> str:
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            row.extend(((x * 37 + y * 17) % 256, (x * 13 + y * 29) % 256, (x * 53 + y * 7) % 256))
        rows.append(bytes(row))
    raw = b''.join(rows)
    png = b'\x89PNG\r\n\x1a\n'
    png += png_chunk(b'IHDR', struct.pack('!IIBBBBB', width, height, 8, 2, 0, 0, 0))
    png += png_chunk(b'IDAT', zlib.compress(raw, 9))
    png += png_chunk(b'IEND', b'')
    return base64.b64encode(png).decode('ascii')

data_uri = 'data:image/png;base64,' + build_png_base64()
openai_payload = {
    'model': '$($Config.voice_vision_model)',
    'messages': [
        {
            'role': 'user',
            'content': 'vois-tu',
        }
    ],
    'files': [
        {
            'type': 'image',
            'url': data_uri,
        }
    ],
    'stream': False,
    'metadata': {},
}

ollama_payload = convert_payload_openai_to_ollama(openai_payload)
ollama_payload = asyncio.run(apply_homelab_ollama_native_images(openai_payload, ollama_payload))

user_messages = [
    message
    for message in ollama_payload.get('messages', [])
    if isinstance(message, dict) and message.get('role') == 'user'
]
user_message = user_messages[-1] if user_messages else {}
images = user_message.get('images') if isinstance(user_message.get('images'), list) else []
first_image = images[0] if images else ''

result = {
    'user_message_count': len(user_messages),
    'content': user_message.get('content', ''),
    'images_count': len(images),
    'first_image_length': len(first_image),
    'first_image_prefix': first_image[:24],
    'first_image_is_url': first_image.startswith('http') or first_image.startswith('/') or first_image.startswith('data:image/'),
}

print('HOMELAB_JSON=' + json.dumps(result))
raise SystemExit(
    0
    if (
        result['user_message_count'] == 1
        and result['content'] == 'vois-tu'
        and result['images_count'] >= 1
        and result['first_image_length'] > 1024
        and not result['first_image_is_url']
    )
    else 2
)
"@

    $rawResult = Invoke-OpenWebUiPythonRaw -Config $Config -PythonCode $pythonCode
    $combinedOutput = ($rawResult.StdOut + [Environment]::NewLine + $rawResult.StdErr).Trim()
    $match = [regex]::Match($combinedOutput, "HOMELAB_JSON=(\{.*\})", [System.Text.RegularExpressions.RegexOptions]::Singleline)

    if (-not $match.Success) {
        if ($rawResult.ExitCode -ne 0) {
            throw (($rawResult.StdErr + [Environment]::NewLine + $rawResult.StdOut).Trim())
        }

        throw "Could not read Open WebUI Ollama native image replay result."
    }

    $result = $match.Groups[1].Value | ConvertFrom-Json
    $result | Add-Member -NotePropertyName ExitCode -NotePropertyValue $rawResult.ExitCode

    return $result
}

function New-OpenWebUiLocalJwtToken {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $pythonCode = @"
from datetime import timedelta
import re
import sqlite3
from open_webui.utils.auth import create_token

conn = sqlite3.connect('/app/backend/data/webui.db')
conn.row_factory = sqlite3.Row
row = conn.execute(
    "select id from user order by case role when 'admin' then 0 else 1 end, created_at limit 1"
).fetchone()

if row is None:
    raise RuntimeError('No Open WebUI user found for local endpoint validation')

token = create_token({'id': row['id']}, expires_delta=timedelta(minutes=5))
print('HOMELAB_JWT=' + token)
"@

    $output = Invoke-OpenWebUiPython -Config $Config -PythonCode $pythonCode
    $match = [regex]::Match($output, "HOMELAB_JWT=([A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+)")

    if (-not $match.Success) {
        throw "Could not create a local Open WebUI JWT for endpoint validation."
    }

    return $match.Groups[1].Value
}

function Clear-OpenWebUiSpeechCache {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $pythonCode = @"
from pathlib import Path

cache_dir = Path('/app/backend/data/cache/audio/speech')
removed = 0

if cache_dir.exists():
    for path in cache_dir.iterdir():
        if path.is_file() and path.suffix.lower() in {'.mp3', '.json'}:
            path.unlink()
            removed += 1

print(f'openwebui-speech-cache-cleared:{removed}')
"@

    return (Invoke-OpenWebUiPython -Config $Config -PythonCode $pythonCode).Trim()
}

function Get-OpenWebUiPersistedConfigJson {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $pythonCode = @"
import sqlite3

conn = sqlite3.connect('/app/backend/data/webui.db')
cur = conn.cursor()
cur.execute('select data from config order by id desc limit 1')
row = cur.fetchone()
if row is None:
    raise RuntimeError('No Open WebUI config row found')
print(row[0])
"@

    return (Invoke-OpenWebUiPython -Config $Config -PythonCode $pythonCode).Trim()
}
