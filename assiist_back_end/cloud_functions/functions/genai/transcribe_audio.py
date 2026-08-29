import os
import tempfile
import logging
import uuid
import json
from pathlib import Path
from typing import Dict, Any

import httpx
from firebase_functions import https_fn, options
from firebase_admin import initialize_app
from openai import OpenAI

# Ensure Firebase Admin is initialised exactly once
import firebase_admin
if not firebase_admin._apps:
    initialize_app()

logger = logging.getLogger(__name__)
options.set_global_options(region="us-central1")

DEFAULT_MODEL = "whisper-1"
OPENAI_AUDIO_MAX_BYTES = 25 * 1024 * 1024  # 25 MB limit
REQUEST_TYPE = "transcription"


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def _download_file(url: str) -> Path:
    """Download *url* to a temporary file and return the path."""
    # Extract file extension from URL
    from urllib.parse import urlparse
    parsed_url = urlparse(url)
    path_parts = parsed_url.path.split('.')
    extension = path_parts[-1] if len(path_parts) > 1 else 'mp3'  # Default to mp3
    
    # Ensure extension is valid for OpenAI
    valid_extensions = ['flac', 'm4a', 'mp3', 'mp4', 'mpeg', 'mpga', 'oga', 'ogg', 'wav', 'webm']
    if extension.lower() not in valid_extensions:
        extension = 'mp3'  # Default fallback
    
    tmp_path = Path(tempfile.gettempdir()) / f"audio_{uuid.uuid4().hex}.{extension}"
    logger.info("Downloading audio file from %s", url)

    with httpx.stream("GET", url, timeout=60) as resp:
        resp.raise_for_status()
        with tmp_path.open("wb") as f:
            for chunk in resp.iter_bytes():
                f.write(chunk)
    logger.info("Downloaded %s (%.2f MB)", tmp_path.name, tmp_path.stat().st_size / 1e6)
    return tmp_path


def _transcribe_file(path: Path, *, model: str = DEFAULT_MODEL) -> str:
    """Call OpenAI Whisper and return the transcription text."""
    client = OpenAI()
    with path.open("rb") as f:
        # Specify filename with extension for OpenAI to detect format
        response = client.audio.transcriptions.create(
            model=model, 
            file=(path.name, f, "audio/mpeg")  # Provide filename with extension
        )
    return response.text  # type: ignore[attr-defined]


# ---------------------------------------------------------------------------
# Cloud Function entry point
# ---------------------------------------------------------------------------

@https_fn.on_request(secrets=["OPENAI_API_KEY"])
def transcribe_audio(req: https_fn.Request) -> https_fn.Response:  # noqa: N802 – Firebase style
    """HTTP Cloud Function to transcribe an audio file using OpenAI Whisper.

    Expected JSON payload::
        {
          "id": "<uuid>",                    # Required – request ID for tracking
          "audio_url": "https://...",        # Required – public URL to the audio file
          "callback_url": "https://...",     # Optional – URL to POST the results to
          "user_id": "...",                  # Optional metadata
          "contact_id": "..."
        }
    """
    if req.method != "POST":
        return https_fn.Response("Method Not Allowed", status=405)

    req_json: Dict[str, Any] | None = req.get_json(silent=True)
    if not req_json:
        return https_fn.Response("Invalid JSON body", status=400)

    request_id = req_json.get("id") or str(uuid.uuid4())
    audio_url = req_json.get("audio_url")
    callback_url = req_json.get("callback_url")

    if not audio_url:
        return https_fn.Response("'audio_url' is required", status=400)

    logger.info("TranscribeAudio %s – starting", request_id)

    try:
        # 1️⃣ Download file
        audio_path = _download_file(audio_url)

        # Size validation – OpenAI limit 25 MB, user may send larger; we fail early
        if audio_path.stat().st_size > OPENAI_AUDIO_MAX_BYTES:
            raise ValueError("Audio file exceeds 25 MB limit after download")

        # 2️⃣ Transcribe
        transcription = _transcribe_file(audio_path)

        result_payload = {
            "success": True,
            "id": request_id,
            "request_type": REQUEST_TYPE,
            "transcription_text": transcription,
        }

        # 3️⃣ Optionally POST back to caller
        if callback_url:
            try:
                httpx.post(callback_url, json=result_payload, timeout=30)
            except Exception as cb_exc:
                logger.error("Callback POST failed: %s", cb_exc)

        logger.info("TranscribeAudio %s – completed", request_id)
        return https_fn.Response(
            json.dumps(result_payload),
            status=200,
            headers={"Content-Type": "application/json"}
        )

    except Exception as exc:
        logger.exception("Transcription failed: %s", exc)
        error_payload = {"success": False, "id": request_id, "request_type": REQUEST_TYPE, "error": str(exc)}
        if callback_url:
            try:
                httpx.post(callback_url, json=error_payload, timeout=30)
            except Exception:
                pass
        return https_fn.Response(
            json.dumps(error_payload),
            status=500,
            headers={"Content-Type": "application/json"}
        )

    finally:
        try:
            if 'audio_path' in locals() and audio_path.exists():
                audio_path.unlink(missing_ok=True)
        except Exception:
            pass 