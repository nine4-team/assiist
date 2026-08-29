import os
import json
import logging
import time
import asyncio
from typing import Dict, Any, Optional
from datetime import datetime, timezone


from firebase_functions import https_fn, options
from firebase_admin import initialize_app
from genai.services.ai_generation_service import get_ai_generation_service
from genai.shared import json_utils




# Initialize Firebase Admin SDK
import firebase_admin
if not firebase_admin._apps:
    initialize_app()

logger = logging.getLogger(__name__)
options.set_global_options(region="us-central1")

def validate_inputs(data: Dict[str, Any]) -> Optional[str]:
    """Validate required fields for get_processed_note."""
    required_keys = ['raw_note']  # Minimal - only need raw note content
    # Optional: 'contact_name'
    
    missing_fields = []
    for field in required_keys:
        value = data.get(field)
        if value is None or (isinstance(value, str) and value.strip() == ''):
            missing_fields.append(field)
    
    if missing_fields:
        return "Missing required fields for get_processed_note: " + ", ".join(missing_fields)
    return None

@https_fn.on_request(
    timeout_sec=540,
    memory=options.MemoryOption.GB_2,
    region="us-central1",
    secrets=["ANTHROPIC_API_KEY", "GEMINI_API_KEY"]
)
def get_processed_note(request: https_fn.Request) -> https_fn.Response:
    """
    HTTP Cloud Function to process raw note content.
    """
    ai_service = get_ai_generation_service()
    
    # --- Webhook validation ---
    if request.method != "POST":
        logger.warning("Received non-POST request")
        return https_fn.Response(
            json.dumps({"success": False, "error": "Invalid request method"}),
            status=405,
            headers={"Content-Type": "application/json; charset=utf-8"}
        )
    
    try:
        logger.info("🔄 get_processed_note Cloud Function started")
        start_time = time.time()
        
        # 1. Parse request
        try:
            req_body = request.get_json()
            if not req_body:
                raise ValueError("Request body is empty or not valid JSON")
        except Exception as e:
            logger.error(f"❌ Error parsing request JSON: {e}")
            return https_fn.Response(
                json.dumps({"success": False, "error": f"Invalid JSON: {str(e)}"}),
                status=400,
                headers={"Content-Type": "application/json; charset=utf-8"}
            )
        
        logger.info(f"📋 Request data keys: {list(req_body.keys())}")
        
        # 2. Validate inputs
        validation_error = validate_inputs(req_body)
        if validation_error:
            logger.error(f"❌ Validation error: {validation_error}")
            return https_fn.Response(
                json.dumps({"success": False, "error": validation_error}),
                status=400,
                headers={"Content-Type": "application/json; charset=utf-8"}
            )
        
        # 3. Extract inputs
        raw_note = req_body.get('raw_note', '')
        contact_name = req_body.get('contact_name')
        id = req_body.get('id')
        user_timezone = req_body.get('user_timezone', 'UTC')
        try:
            from zoneinfo import ZoneInfo
            tz = ZoneInfo(user_timezone)
        except Exception:
            tz = timezone.utc
        current_date = datetime.now(tz).strftime("%A, %B %d, %Y at %I:%M %p %Z")
        
        logger.info(f"📝 Processing note content for: {contact_name}")
        logger.info(f"📄 Note content length: {len(raw_note)} characters")
        
        # 4. Build prompt
        prompt = f"""
        
You are an expert at processing notes.

Raw Note: {raw_note}
Contact Name: {contact_name}
Current Date: {current_date}

TASK: Clean up this raw note and extract key points.  
The cleaned content should be a paragraphically written and grammatically correct version written from the perspective of the user.

IMPORTANT RULES:
- cleaned_content and key_points must be written from the perspective of the user.
- DO NOT invent any information that is not in the raw note.
- DO NOT remove any information when creating cleaned_content.  ONLY modify the raw note for readability and grammatical correctness.
- Avoid language in cleaned_content that could lead to misinterpretation.
- Ensure cleaned_content is clear, concise, and well-structured.
- AVOID key points that are redundant with each other or low-value.
- If there is a URL in the raw note, it must be included in cleaned_content.

VALIDATION STEPS:
- For each rule, ask: "Is the rule violated?"
- If yes, then modify the output and retest until all rules are satisfied.

Please provide your response as a JSON object with this exact structure:

{{
    "cleaned_content": A paragraphically written and grammatically correct version of the input notes that maintains all details and does not invent any information,
    "key_points": [Optional list of key insights, motivations, and important context]
}}

Respond only with the JSON object, no additional text."""

        # 5. Prepare messages for different AI providers
        anthropic_messages = [
            {
                "role": "user",
                "content": prompt
            }
        ]
        
        gemini_prompt_text = prompt
        
        logger.info("🧠 Calling AI service for note processing")
        
        # 6. Call AI service using standardized method
        response_text, provider, error_message = asyncio.run(ai_service.execute_llm_call(
            anthropic_messages=anthropic_messages,
            gemini_prompt_text=gemini_prompt_text,
            temperature=0.3,
            max_tokens=1024,
            gemini_response_mime_type="application/json"
        ))
        
        # Get the actual model name based on the provider used
        model = ai_service._anthropic_model if provider == "anthropic" else ai_service._gemini_model_name
        
        if error_message:
            logger.error(f"❌ AI service error: {error_message}")
            error_payload = {
                "success": False,
                "error": f"AI processing failed: {error_message}",
                "type": "process_note"
            }
            
                        # Call callback with error if provided
            callback_url = req_body.get('callback_url')
            if callback_url and id:
                callback_payload = {
                    "id": id,
                    "request_type": "process_note",
                    "callback_url": callback_url,  # ✅ Include callback URL in error callback
                    **error_payload
                }
                
                try:
                    import requests
                    requests.post(callback_url, json=callback_payload, timeout=30)
                except:
                    pass
            
            return https_fn.Response(
                json.dumps(error_payload),
                status=500,
                headers={"Content-Type": "application/json; charset=utf-8"}
            )
        
        # 7. Parse and validate AI response
        try:
            extraction_result = json_utils.extract_json(response_text, debug=True)
            parsed_json_str = extraction_result.get('extracted_json')
            
            if not parsed_json_str:
                raise ValueError("Failed to extract JSON from AI response")
            
            ai_results = json.loads(parsed_json_str)
            if not ai_results:
                raise ValueError("Failed to parse AI response as JSON")
        except Exception as e:
            logger.error(f"❌ Failed to parse AI response: {e}")
            # Fallback: return simplified structured data
            ai_results = {
                "cleaned_content": raw_note,
                "key_points": ["Note processing failed - using original content"]
            }
        
        # 8. Validate required fields in AI response
        if not isinstance(ai_results, dict):
            ai_results = {
                "cleaned_content": raw_note,
                "key_points": ["Invalid AI response format"]
            }
        
        # Ensure required fields exist
        cleaned_content = ai_results.get("cleaned_content", raw_note)
        key_points = ai_results.get("key_points", [])
        
        if not isinstance(key_points, list):
            key_points = ["Failed to extract key points"]
        
        # Clean AI results - only AI-generated content
        clean_ai_results = {
            "cleaned_content": cleaned_content,
            "key_points": key_points
        }
        
        # 9. Prepare success response with separated structure
        processing_time = time.time() - start_time
        
        success_payload = {
            "success": True,
            "type": "process_note",
            "processed_note": clean_ai_results,  # ✅ Clean AI results only
            "llm_provider": provider,             # ✅ Metadata separate
            "llm_model": model,                   # ✅ Actual model name (not provider)
            "processing_time_ms": int(processing_time * 1000),  # ✅ Standardized field name
            "raw_note": raw_note,       # ✅ Consistent field naming
            "contact_name": contact_name,         # ✅ Metadata separate
            "thinking_enabled": getattr(ai_service, "_last_thinking_enabled", False),
            "thinking_budget_tokens": getattr(ai_service, "_last_thinking_budget", None)
        }
        
        logger.info(f"✅ Note processing completed successfully in {processing_time:.2f}s")
        logger.info(f"📊 Extracted {len(key_points)} key points from {len(cleaned_content)} character cleaned content")
        
        # 10. CRITICAL: Call back to API with results (callback mechanism)
        callback_url = req_body.get('callback_url')
        if callback_url and id:
            logger.info(f"🔗 CALLING CALLBACK: {callback_url}")
            
            callback_payload = {
                "id": id,
                "request_type": "process_note",
                "callback_url": callback_url,  # ✅ Include the callback URL used
                **success_payload  # Include all results
            }
            
            try:
                import requests
                response = requests.post(
                    callback_url,
                    json=callback_payload,
                    headers={"Content-Type": "application/json; charset=utf-8"},
                    timeout=30
                )
                
                if response.status_code == 200:
                    logger.info(f"✅ Successfully called back to API for request {id}")
                else:
                    logger.error(f"❌ Callback failed: {response.status_code} - {response.text}")
            except Exception as callback_error:
                logger.error(f"❌ Error calling back to API: {callback_error}")
        else:
            logger.info("ℹ️ No callback URL provided - returning results directly")
        
        # 11. Return success response
        return https_fn.Response(
            json.dumps(success_payload),
            status=200,
            headers={"Content-Type": "application/json; charset=utf-8"}
        )
        
    except Exception as e:
        logger.error(f"❌ Unexpected error in get_processed_note: {e}")
        
        error_payload = {
            "success": False,
            "error": str(e),
            "type": "process_note"
        }
        
        # Try to call callback with error
        try:
            req_body = request.get_json() or {}
            callback_url = req_body.get('callback_url')
            id = req_body.get('id')
            
            if callback_url and id:
                callback_payload = {
                    "id": id,
                    "request_type": "process_note",
                    "callback_url": callback_url,  # ✅ Include callback URL in final error callback
                    **error_payload
                }
                
                import requests
                requests.post(callback_url, json=callback_payload, timeout=30)
        except:
            pass
        
        return https_fn.Response(
            json.dumps(error_payload),
            status=500,
            headers={"Content-Type": "application/json; charset=utf-8"}
        )

# Note: Local testing now requires Firebase Functions emulator
# No main function - this follows Firebase Functions pattern 