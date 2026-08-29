import logging
import json
from typing import Dict, Any

import functions_framework  # type: ignore
from firebase_functions import https_fn, options
from firebase_admin import initialize_app
from openai import OpenAI
import requests
from genai.shared import json_utils

# Ensure Firebase Admin is initialised exactly once
import firebase_admin
if not firebase_admin._apps:
    initialize_app()

logger = logging.getLogger(__name__)
options.set_global_options(region="us-central1")
REQUEST_TYPE = "extract_call_insights"

def _build_prompt(data: Dict[str, Any]) -> str:
    """Generate a concise prompt for extracting call insights for the Assiist app."""
    
    transcription = data.get("transcription_text", "")
    
    return f"""Create a concise summary of this phone call transcript, cutting out the fluff and capturing the essential information.

TASK: Read the phone-call transcript and return a concise cliff-notes style summary without fluff or inference
Write from the user's first-person perspective ("I learned...", "We discussed...", "<Contact Name> mentioned...") as flowing paragraphs in a casual, natural tone. 

If present, make sure to include:
- **Personal details** about the contact (family, occupation, hobbies, goals)
- **Business opportunities** (blockers, deals, partnerships, developments)
- **Action items** (tasks, commitments, follow-ups, deadlines)

If the transcript lacks personal details, business context, or action items, simply omit them.  Don't even mention they weren't there.

Transcript
----------
{transcription}

Respond ONLY with a valid JSON object:
{{
  "summary": "<your brief summary here>"
}}
"""

@https_fn.on_request(secrets=["OPENAI_API_KEY"])
def extract_call_insights(req: https_fn.Request) -> https_fn.Response:  # noqa: N802
    """HTTP Cloud Function that takes a transcript and extracts key insights."""
    if req.method != "POST":
        return https_fn.Response("Method Not Allowed", status=405)

    data: Dict[str, Any] | None = req.get_json(silent=True)
    if not data or "transcription_text" not in data:
        return https_fn.Response("Missing transcription_text", status=400)

    # Retrieve callback URL (for async result handling)
    callback_url = data.get("callback_url")

    request_id = data.get("id") or "unknown"
    transcription_text: str = data["transcription_text"][:16000]  # Safe limit

    try:
        client = OpenAI()
        prompt = _build_prompt(data)
        chat_resp = client.chat.completions.create(
            model="gpt-4.1-2025-04-14",  # Use the specified model
            messages=[{"role": "system", "content": prompt}],
            temperature=0.3,
        )
        content = chat_resp.choices[0].message.content or "{}"

        # Robust JSON extraction (handles ```json fences, trailing text, etc.)
        extraction = json_utils.extract_json(content, debug=False)
        extracted_json = extraction.get("extracted_json")
        summary: str
        if extracted_json:
            try:
                parsed_json = json.loads(extracted_json)
                summary = parsed_json.get("summary", "").strip()
            except Exception:
                summary = extraction.get("extra_text", content).strip()
        else:
            # Fallback: treat raw content as summary
            summary = extraction.get("extra_text", content).strip()

        payload = {
            "success": True,
            "id": request_id,
            "request_type": REQUEST_TYPE,
            "summary": summary,
        }

        # Optionally POST the results back to caller for asynchronous processing
        if callback_url:
            try:
                requests.post(callback_url, json=payload, timeout=30)
            except Exception as cb_exc:
                logger.error("Callback POST failed: %s", cb_exc)

        return https_fn.Response(
            json.dumps(payload),
            status=200,
            headers={"Content-Type": "application/json"}
        )

    except Exception as exc:
        logger.exception("Call insights extraction failed: %s", exc)
        error_payload = {"success": False, "id": request_id, "request_type": REQUEST_TYPE, "error": str(exc)}

        # Attempt callback if URL provided
        if callback_url:
            try:
                requests.post(callback_url, json=error_payload, timeout=30)
            except Exception:
                pass

        return https_fn.Response(
            json.dumps(error_payload),
            status=500,
            headers={"Content-Type": "application/json"}
        ) 