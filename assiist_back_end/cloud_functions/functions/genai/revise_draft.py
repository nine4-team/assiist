# Main file for the revise_message_draft Cloud Function

import os
import json
import logging
from typing import Dict, Any, Optional
import time
import requests

# Firebase Functions imports
from firebase_functions import https_fn, options
from firebase_admin import initialize_app, firestore
from google.cloud.firestore_v1 import AsyncClient

# Import local modules
from genai.services.ai_generation_service import get_ai_generation_service
from genai.shared import url_utils
from genai.shared import json_utils

# Initialize Firebase Admin SDK (ensure it runs only once)
import firebase_admin
if not firebase_admin._apps:
    initialize_app()

logger = logging.getLogger(__name__)
options.set_global_options(region="us-central1")

# --- Constants ---
# Expected keys from AI output for revision
EXPECTED_AI_OUTPUT_KEYS = ["text_message", "assistant_message", "task_title"]

# --- Validation Helper ---

def validate_inputs_for_revision(data: Dict[str, Any]) -> Optional[str]:
    """Validate required fields for revise_message_draft.

    Args:
        data (dict): The input data dictionary (customData).

    Returns:
        str or None: An error message string if validation fails, otherwise None.
    """
    # Validate only fields needed for AI processing (NO database routing IDs)
    # Database IDs (user_id, contact_id, task_id) are stored in Firestore, not needed for AI processing
    
    missing_fields = []
    # Define required keys for revision AI processing
    required_keys = [
        'message_draft',           # The draft being revised
        'revision_history',        # Required context for AI
        'recipient_name',          # Need recipient name for personalization
        'recipient_phone',         # Need recipient phone for SMS URL generation
        'revision_instructions',   # Required for this revision
        'message_language',        # Required for language selection
        'user_first_name',         # Required for sender context
        'business_name',           # Required for business context
        'business_type'            # Required for business context
        # Optional fields with defaults: 'language_examples' (defaults to "")
        # Database IDs like user_id, contact_id, task_id are retrieved from Firestore when needed
    ]

    # Add debug logging to see what we're receiving
    logger.info(f"Validating revision request with data keys: {list(data.keys())}")
    logger.info(f"Full payload: {json.dumps(data, indent=2)}")
    
    # CRITICAL FIX: Convert language_examples from list to string if needed, or provide blank default
    if 'language_examples' in data:
        if isinstance(data['language_examples'], list):
            # Convert list to string format expected by cloud function
            if data['language_examples']:
                data['language_examples'] = '\n'.join(str(example) for example in data['language_examples'])
            else:
                data['language_examples'] = ""  # Empty list becomes empty string
            logger.info(f"✅ Converted language_examples from list to string: {len(data['language_examples'])} chars")
    else:
        # Provide blank default if missing
        data['language_examples'] = ""
        logger.info(f"✅ Provided blank default for missing language_examples")
    
    for field in required_keys:
        value = data.get(field)
        logger.info(f"Field '{field}': value='{value}', type={type(value)}")
        
        if value is None or (isinstance(value, str) and value.strip() == ''):
            missing_fields.append(field)
            logger.warning(f"Field '{field}' is missing or empty")

    if missing_fields:
        error_msg = "Missing required fields for revise_message_draft: " + ", ".join(missing_fields)
        logger.error(f"Validation failed: {error_msg}")
        return error_msg
    
    logger.info("Validation passed successfully")
    return None

def create_revision_prompt(data: Dict[str, Any]) -> str:
    """Create the detailed AI prompt for message revision.
    
    Args:
        data (dict): The request data containing message details
        
    Returns:
        str: The formatted prompt for the AI
    """
    message_language = data.get("message_language", "English")
    language_instruction = "Generate all messages in conversational Mexican Spanish." if message_language.lower() == "spanish" else "Generate all messages in English."
    
    user_first_name = data.get('user_first_name', '')
    business_name = data.get('business_name', '')
    business_type = data.get('business_type', '')
    
    # Format owner description
    owner_description = user_first_name
    if business_name:
        owner_description += f" (business owner of {business_name})"
    elif business_type:
        owner_description += f" (the {business_type})"
        
    # Prepare detailed user message for AI
    return f"""You are an expert message editor specializing in SMS communication.

Your primary task is to revise the DRAFT TO REVISE provided in the parameters below, following the RULES and generating the output specified in the TASK section.

--- PARAMETERS & CONTEXT ---

OUTPUT LANGUAGE: {language_instruction}

SENDER: {owner_description}
RECIPIENT: {data.get('recipient_name', '')}

SENDER'S WRITING STYLE EXAMPLES:
```
{data.get('language_examples', '')}
```

REVISION HISTORY (includes original context and previous revisions):
```
{data.get('revision_history', '')}
```

REVISION INSTRUCTIONS (Specific changes for *this* revision):
```
{data.get('revision_instructions', '')}
```

DRAFT TO REVISE:
```
{data.get('message_draft', '')}
```

--- RULES & GUIDELINES ---

- Prioritization: The REVISION INSTRUCTIONS section above takes precedence over all other guidelines. The REVISION INSTRUCTIONS *override* any conflicting constraints from WRITING STYLE or REVISION HISTORY.
- Persistent Style (History): Formatting and stylistic choices applied in previous revisions (e.g., all caps, specific emojis, phrasing) as shown in REVISION HISTORY must be preserved in the new revision *unless explicitly changed by the current REVISION INSTRUCTIONS*. The REVISION HISTORY acts as a set of active constraints.
- Consistency (Writing Style): Maintain consistency with the sender's WRITING STYLE (tone, formality, punctuation, emoji usage, etc.) derived from the examples, *only when it does not conflict with REVISION INSTRUCTIONS or the established style in REVISION HISTORY*.
- Conflict Resolution: If there are direct conflicts between instructions and history, prioritize the latest REVISION INSTRUCTIONS, then the active constraints established by the REVISION HISTORY (most recent revision first). Only then consider the WRITING STYLE examples.
- History Awareness: Consider the REVISION HISTORY to understand the message's evolution and the sender's intent refinement over time. This context is crucial for applying Persistent Style correctly.
- Conciseness: Keep the message concise for SMS (ideally under 320 characters).
- Information Integrity: Do not assume or invent any information not present in the provided parameters and context.

--- TASK ---

1. Generate the revised text message based *only* on the parameters and rules above.
2. Create a brief, friendly assistant message for the sender introducing the revised message.
3. Create a very short task title capturing the nature of the revised message.

--- OUTPUT FORMAT (Strict JSON) ---

Provide your response *only* as a JSON object matching this structure exactly:
{{
  "text_message": "The fully revised text message, ready to send.",
  "assistant_message": "A brief, friendly introductory phrase for the sender.",
  "task_title": "Your task title here (very short)."
}}"""

# --- Main Handler --- #
@https_fn.on_request(secrets=["ANTHROPIC_API_KEY", "GEMINI_API_KEY"])
def revise_message_draft(req: https_fn.Request) -> https_fn.Response:
    """HTTPS Cloud Function to revise a message draft."""
    start_time = time.time()
    status = "failed"
    error = None
    provider = None
    model = None
    llm_response = None
    result = None
    prompt = None
    user_id = None
    contact_id = None
    instructions = None
    task_id = None
    try:
        if req.method != 'POST':
            logger.warning(f"Method Not Allowed: Received {req.method} request.")
            return https_fn.Response(
                json.dumps({
                    "success": False,
                    "error": f"Method {req.method} not allowed. Only POST is supported."
                }),
                status=405,
                mimetype="application/json"
            )

        req_body = req.get_json(silent=True)
        if not req_body or not isinstance(req_body, dict):
            logger.error("Request body is missing or invalid JSON.")
            return https_fn.Response(
                json.dumps({
                    "success": False,
                    "error": "Request body is missing or invalid JSON."
                }),
                status=400,
                mimetype="application/json"
            )

        logger.info("revise_message_draft function invoked.")
        data = req_body
        
        # DEBUG: Log what we actually received
        logger.info(f"🐛 RECEIVED DATA KEYS: {list(data.keys())}")
        logger.info(f"🐛 CALLBACK_URL PRESENT: {'callback_url' in data}")
        logger.info(f"🐛 ID PRESENT: {'id' in data}")
        if 'callback_url' in data:
            logger.info(f"🐛 CALLBACK_URL VALUE: {data['callback_url']}")
        if 'id' in data:
            logger.info(f"🐛 ID VALUE: {data['id']}")
        
        # Extract required fields for logging
        user_id = data.get('user_id')
        contact_id = data.get('contact_id')
        instructions = data.get('revision_instructions')
        task_id = data.get('task_id')

        # 2. Input Validation
        validation_error = validate_inputs_for_revision(data)
        if validation_error:
            logger.error(f"Input validation failed: {validation_error}")
            return https_fn.Response(
                json.dumps({
                    "success": False,
                    "type": "revise_draft",
                    "error": validation_error
                }),
                status=400,
                mimetype="application/json"
            )

        # 3. Get AI service
        ai_service = get_ai_generation_service()
        if not ai_service:
            logger.critical("AI Generation Service could not be initialized.")
            return https_fn.Response(
                json.dumps({
                    "success": False,
                    "error": "Internal server error: AI Service unavailable."
                }),
                status=500,
                mimetype="application/json"
            )

        # 4. Create AI prompt (already includes system content)
        logger.info("Creating revision prompt...")
        prompt = create_revision_prompt(data)

        # 5. Call AI service
        logger.info("Calling AI generation service...")
        
        # Create formatted prompts for both Anthropic and Gemini
        anthropic_messages = [
            {"role": "user", "content": prompt}
        ]
        gemini_prompt_text = prompt
        
        # Use the execute_llm_call method without system prompt
        import asyncio
        response_text, provider, error_message = asyncio.run(ai_service.execute_llm_call(
            anthropic_messages=anthropic_messages,
            gemini_prompt_text=gemini_prompt_text,
            temperature=0.3,
            max_tokens=1024,
            gemini_response_mime_type="application/json"
        ))
        
        model = ai_service._anthropic_model if provider == "anthropic" else ai_service._gemini_model_name
        llm_response = response_text

        if error_message:
            logger.error(f"AI generation failed: {error_message}")
            raise Exception(f"AI generation failed: {error_message}")

        if not response_text:
            logger.error("AI generation returned no text content.")
            raise Exception("AI generation returned no content.")

        logger.info(f"AI generation successful using {provider}.")

        # 6. Extract JSON from AI Response
        extraction_result = json_utils.extract_json(response_text)
        parsed_json_str = extraction_result.get('extracted_json')
        extra_text = extraction_result.get('extra_text')

        if not parsed_json_str:
            logger.error(f"Failed to extract valid JSON from {provider} response.")
            logger.debug(f"Raw response text from {provider}: {response_text}")
            raise Exception("AI response format error: Could not parse JSON.")

        try:
            ai_output = json.loads(parsed_json_str)
            revised_message = ai_output.get('text_message')
            assistant_message = ai_output.get('assistant_message')
            task_title = ai_output.get('task_title')

            if not all([revised_message, assistant_message, task_title]):
                logger.error(f"AI JSON response missing required keys. Found: {ai_output.keys()}")
                raise Exception("AI response incomplete: Missing required fields.")

        except json.JSONDecodeError as e:
            logger.error(f"Error decoding extracted JSON: {e}")
            logger.debug(f"Extracted JSON string: {parsed_json_str}")
            raise Exception("AI response format error: Invalid JSON structure.") from e

        # 7. Generate SMS URL for revised message
        logger.info("Generating SMS URL...")
        contact_phone = data.get('recipient_phone')
        sms_url = url_utils.generate_sms_url(
            message=revised_message,
            phone_number=contact_phone,
            platform="ios"
        )

        # 8. Prepare success response with standardized metadata
        processing_time_ms = int((time.time() - start_time) * 1000)
        success_payload = {
            "success": True,
            "type": "revise_draft",
            "message": revised_message,
            "assistant_message": assistant_message,
            "task_title": task_title,
            "sms_url": sms_url,
            "llm_provider": provider,
            "llm_model": model,  # ADD: specific model used
            "processing_time_ms": processing_time_ms,  # ADD: processing time
            "thinking_enabled": getattr(ai_service, "_last_thinking_enabled", False),
            "thinking_budget_tokens": getattr(ai_service, "_last_thinking_budget", None)
        }
        
        # 9. CRITICAL: Call back to API with results (callback mechanism)
        callback_url = data.get('callback_url')
        id = data.get('id')
        
        if callback_url and id:
            logger.info(f"🔗 CALLING CALLBACK: {callback_url}")
            logger.info(f"📊 Callback payload keys: {list(success_payload.keys())}")
            
            # Prepare callback payload with request metadata
            callback_payload = {
                "id": id,
                "request_type": "revise_draft",
                "callback_url": callback_url,  # ✅ Include the callback URL used
                **success_payload  # Include all AI results
            }
            
            try:
                import requests
                
                # Call back to API with results
                response = requests.post(
                    callback_url,
                    json=callback_payload,
                    headers={
                        "Content-Type": "application/json; charset=utf-8"
                    },
                    timeout=30
                )
                
                if response.status_code == 200:
                    logger.info(f"✅ Successfully called back to API for request {id}")
                else:
                    logger.error(f"❌ Callback failed: {response.status_code} - {response.text}")
                    
            except Exception as callback_error:
                logger.error(f"❌ Error calling back to API: {callback_error}")
                # Don't fail the entire function - just log the error
        else:
            logger.warning("⚠️ No callback_url or id provided - skipping callback")
        
        logger.info("revise_message_draft completed successfully.")
        status = "success"
        result = success_payload
        return https_fn.Response(
            json.dumps(success_payload, ensure_ascii=False).encode('utf-8'), 
            status=200, 
            mimetype="application/json; charset=utf-8"
        )

    except Exception as e:
        error = str(e)
        logger.error(f"Critical error in revise_message_draft: {e}", exc_info=True)
        error_payload = {
            "success": False,
            "type": "revise_draft",
            "error": f"Internal server error: {e}"
        }
        
        # CRITICAL: Call back to API with error results if possible
        callback_url = None
        id = None
        try:
            if req_body:
                callback_url = req_body.get('callback_url')
                id = req_body.get('id')
                
            if callback_url and id:
                logger.info(f"🔗 CALLING ERROR CALLBACK: {callback_url}")
                
                # Prepare error callback payload
                callback_payload = {
                    "id": id,
                    "request_type": "revise_draft",
                    "callback_url": callback_url,  # ✅ Include callback URL in error callback
                    **error_payload  # Include error details
                }
                
                try:
                    import requests
                    
                    # Call back to API with error results
                    response = requests.post(
                        callback_url,
                        json=callback_payload,
                        headers={
                            "Content-Type": "application/json; charset=utf-8"
                        },
                        timeout=30
                    )
                    
                    if response.status_code == 200:
                        logger.info(f"✅ Successfully called back to API with error for request {id}")
                    else:
                        logger.error(f"❌ Error callback failed: {response.status_code} - {response.text}")
                        
                except Exception as callback_error:
                    logger.error(f"❌ Error calling back to API with error: {callback_error}")
            else:
                logger.warning("⚠️ No callback_url or id available for error callback")
                
        except Exception as callback_setup_error:
            logger.error(f"❌ Error setting up error callback: {callback_setup_error}")
        
        return https_fn.Response(
            json.dumps(error_payload, ensure_ascii=False).encode('utf-8'), 
            status=500, 
            mimetype="application/json; charset=utf-8"
        )
    finally:
        # Log completion info
        completed_at = time.time()
        duration_ms = int((completed_at - start_time) * 1000)
        logger.info(f"revise_message_draft completed in {duration_ms}ms with status: {status}") 