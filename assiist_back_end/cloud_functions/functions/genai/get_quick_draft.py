# Cloud Function: get_quick_draft - AI generation service fixes applied
# Updated: 2025-06-17 - AsyncAnthropic client and Gemini safety retry logic

import os
import json
import logging
import time
import asyncio
from typing import Dict, Any, Optional

from firebase_functions import https_fn, options
from firebase_admin import initialize_app, firestore
from genai.services.ai_generation_service import get_ai_generation_service
from genai.shared import url_utils
from genai.shared import json_utils

# Initialize Firebase Admin SDK (ensure it runs only once)
import firebase_admin
if not firebase_admin._apps:
    initialize_app()

logger = logging.getLogger(__name__)
options.set_global_options(region="us-central1") # Example region

# --- Constants ---
# Consider defining expected output keys, etc.

# --- Helper Functions (e.g., prompt generation specific to quick draft) ---

def generate_quick_draft_user_prompt(params: Dict[str, Any]) -> str:
    """Generates the user prompt text specifically for the quick draft request."""
    # Extract necessary parameters from params dict
    language = params.get('message_language', 'English')  # Default language matching JS version
    user_first_name = params.get('user_first_name', 'User')  # User's first name
    business_name = params.get('business_name', None)
    business_type = params.get('business_type', None)
    recipient_name = params.get('recipient_name', 'Contact')  # Contact's name
    message_instructions = params.get('message_instructions', '')
    language_examples = params.get('language_examples', '')  # User's text message examples

    # Language instruction
    lang_instruction = 'Generate all messages in conversational Mexican Spanish.' \
                       if language == 'Spanish' else 'Generate all messages in English.'

    # Construct the prompt text with system content inline
    prompt_text = f"""You are an expert message writer who can perfectly match the tone, style, and language patterns of any person. 
{lang_instruction}
You'll generate three different messages following the user's instructions precisely:

1. A text message from a business owner to their contact
2. A helpful assistant message to the business owner about the generated text
3. A very short task title describing what's being sent

I need you to write three different messages. {lang_instruction}

PART 1: TEXT MESSAGE TO RECIPIENT

User: {user_first_name}
Business Name: {business_name}
Business Type: {business_type}

Write a text message from {user_first_name} to {recipient_name} (contact).

MESSAGE REQUIREMENTS:
{message_instructions}

WRITING STYLE FOR TEXT MESSAGE:
Below are examples of {user_first_name}'s actual text message style and tone. Your message should match this style perfectly:
```
{language_examples}
```

CRITICAL RULES FOR TEXT MESSAGE:
1. Include a natural greeting that matches the business owner's style
2. Keep the message concise and appropriate for SMS but do not exclude key things just to shorten it
3. Match the casual/formal level exactly to the examples
4. Use the same punctuation patterns, emoji style, abbreviations, and capitalization as shown in the examples
5. The message should be personalized to {recipient_name}
6. The final draft must be ready to send as-is without any need for editing

PART 2: ASSISTANT MESSAGE TO BUSINESS OWNER
Create a brief, helpful message from an AI assistant to {user_first_name} about the text message you've generated.

CRITICAL RULES FOR ASSISTANT MESSAGE:
1. Keep it concise (under 100 characters if possible)
2. Use a friendly, professional tone
3. Focus only on what the message is FOR, not HOW it was created
4. Start with a greeting.
5. Don't include the URL (it will be added separately)

PART 3: TASK TITLE
Create a very short title (under 50 characters) that describes what's being sent in language that is natural and easy to understand, loosely following this template.
"Send {recipient_name} the message you requested about <topic>"

CRITICAL RULES FOR TASK TITLE:
1. Keep it under 50 characters
2. Don't include any technical details or implementation specifics

Format your response exactly like this:
```json
{{
  "text_message": "Your text message here",
  "assistant_message": "Your assistant message here (without URL)",
  "task_title": "Your task title here"
}}
```
Ensure the output is nothing but this JSON object.
"""
    return prompt_text


def validate_inputs(data: Dict[str, Any]) -> Optional[str]:
    """Validate required fields for get_quick_draft.

    Args:
        data (dict): The input data dictionary (customData).

    Returns:
        str or None: An error message string if validation fails, otherwise None.
    """
    missing_fields = []
    # Define required keys for AI processing (NO database routing IDs)
    # Database IDs (user_id, contact_id) are stored in Firestore, not needed for AI processing
    required_keys = [
        'recipient_phone',        # needed for SMS URL generation
        'recipient_name',         # needed for message personalization
        'user_first_name',        # needed for message context
        'message_instructions',   # needed for AI generation
        'business_name',          # needed for business context
        'business_type'           # needed for business context
        # Optional fields with defaults: 'message_language' (defaults to 'English'), 'language_examples' (defaults to "")
        # Database IDs like user_id, contact_id are retrieved from Firestore when needed for callbacks
    ]

    # CRITICAL FIX: Convert language_examples from list to string if needed
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
        if value is None or (isinstance(value, str) and value.strip() == ''):
            missing_fields.append(field)

    if missing_fields:
        return "Missing required fields for get_quick_draft: " + ", ".join(missing_fields)
    return None


# --- Main Handler --- #
# Define secrets and parameters needed
@https_fn.on_request(secrets=["ANTHROPIC_API_KEY", "GEMINI_API_KEY"])
def get_quick_draft(req: https_fn.Request) -> https_fn.Response:
    """HTTPS Cloud Function to generate a quick message draft."""
    # 1. Basic Checks & Request Body Parsing
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
    try:
        if req.method != 'POST':
            logger.warning(f"Method Not Allowed: Received {req.method} request.")
            return https_fn.Response("Method Not Allowed", status=405)

        req_body = req.get_json(silent=True)
        if not req_body or not isinstance(req_body, dict):
            logger.error("Request body is missing or invalid JSON.")
            return https_fn.Response(json.dumps({"success": False, "error": "Request body is missing or invalid JSON."}), status=400, mimetype="application/json")

        logger.info("get_quick_draft function invoked.")
        # Use request body directly - no need for customData wrapper
        if not isinstance(req_body, dict):
             logger.error("Request body is not a valid dictionary.")
             return https_fn.Response(json.dumps({"success": False, "error": "Invalid data structure in request."}), status=400, mimetype="application/json")

        user_id = req_body.get('user_id')
        contact_id = req_body.get('contact_id')
        instructions = req_body.get('message_instructions')
        message_language = req_body.get('message_language', 'english')  # Fix: Define message_language variable

        # 2. Input Validation
        validation_error = validate_inputs(req_body)
        if validation_error:
            logger.error(f"Input validation failed: {validation_error}")
            return https_fn.Response(json.dumps({"success": False, "type": "quick_draft", "error": validation_error, "data": None}), status=400, mimetype="application/json")

        # 3. Extract Parameters needed for generation and URL
        recipient_phone = req_body.get('recipient_phone')

        # DEBUG: Check what's happening with AI service initialization
        logger.info("🔍 DEBUG: About to call get_ai_generation_service()")
        ai_service = get_ai_generation_service()
        logger.info(f"🔍 DEBUG: AI service returned: {ai_service}")
        logger.info(f"🔍 DEBUG: AI service type: {type(ai_service)}")
        
        if not ai_service:
            logger.critical("AI Generation Service could not be initialized.")
            return https_fn.Response(json.dumps({"success": False, "error": "Internal server error: AI Service unavailable."}), status=500, mimetype="application/json")

        # Generate prompts following the working JavaScript pattern
        logger.info("Calling AI generation service...")
        
        # Create user prompt with inline system content
        user_prompt = generate_quick_draft_user_prompt(req_body)
        
        # Create formatted prompts for both Anthropic and Gemini
        anthropic_messages = [
            {"role": "user", "content": user_prompt}
        ]
        gemini_prompt_text = user_prompt
        
        # Use the execute_llm_call method without system prompt
        response_text, provider, error_message = asyncio.run(ai_service.execute_llm_call(
            anthropic_messages=anthropic_messages,
            gemini_prompt_text=gemini_prompt_text,
            temperature=0.3,  # Match JS version
            max_tokens=1024,  # Match JS version
            gemini_response_mime_type="application/json"
        ))
        model = ai_service._anthropic_model if provider == "anthropic" else ai_service._gemini_model_name
        llm_response = response_text

        if error_message:
            logger.error(f"AI generation failed: {error_message}")
            raise Exception(f"AI generation failed: {error_message}") # Propagate error

        if not response_text:
            logger.error("AI generation returned no text content.")
            raise Exception("AI generation returned no content.")

        logger.info(f"AI generation successful using {provider}.")

        # 6. Extract JSON from AI Response
        logger.info(f"🔍 Raw AI response from {provider}: {response_text}")
        extraction_result = json_utils.extract_json(response_text, debug=True)
        parsed_json_str = extraction_result.get('extracted_json')
        extra_text = extraction_result.get('extra_text') # Log or handle extra text if needed

        logger.info(f"🔍 JSON extraction result: extracted_json={parsed_json_str}, extra_text={extra_text}")

        if not parsed_json_str:
            logger.error(f"Failed to extract valid JSON from {provider} response.")
            logger.error(f"Raw response text from {provider}: {response_text}")
            logger.error(f"Extraction result: {extraction_result}")
            raise Exception("AI response format error: Could not parse JSON.")

        try:
            if parsed_json_str is None:
                logger.error("Parsed JSON string is None - cannot decode")
                raise Exception("AI response format error: No JSON found in response.")
            
            logger.info(f"🔍 About to parse JSON string: {parsed_json_str}")
            ai_output = json.loads(parsed_json_str)
            
            if ai_output is None:
                logger.error("json.loads returned None")
                raise Exception("AI response format error: JSON parsing returned None.")
            
            logger.info(f"🔍 Parsed AI output: {ai_output}")
            generated_message = ai_output.get('text_message')
            assistant_message = ai_output.get('assistant_message') # Message before URL
            task_title = ai_output.get('task_title')

            if not all([generated_message, assistant_message, task_title]):
                logger.error(f"AI JSON response missing required keys (text_message, assistant_message, task_title). Found: {ai_output.keys()}")
                raise Exception("AI response incomplete: Missing required fields.")

        except json.JSONDecodeError as e:
            logger.error(f"Error decoding extracted JSON: {e}")
            logger.error(f"Extracted JSON string: {parsed_json_str}")
            raise Exception("AI response format error: Invalid JSON structure.") from e

        # 7. Generate SMS URL
        logger.info("Generating SMS URL...")
        sms_url = url_utils.generate_sms_url(
            message=generated_message,
            phone_number=recipient_phone,
            platform="ios"  # Default platform for iPhone
        )

        # Combine assistant message with SMS URL
        final_assistant_message = f"{assistant_message} {sms_url}"

        # 8. Prepare task data for API to create
        logger.info("Preparing task data for API...")
        
        task_data = {
            "title": task_title,
            "body": generated_message,
            "type": "message",
            "status": "pending",
            "llm_provider": provider,
            "sms_url": sms_url,
            "assistant_message": assistant_message
        }
        
        # 9. Prepare revision context for API
        revision_context = {
            "original_instructions": instructions,
            "language": message_language,  # Use the defaulted message_language
            "recipient_name": req_body.get('recipient_name'),  # aligned with revise_draft
            "user_first_name": req_body.get('user_first_name'),
            "business_name": req_body.get('business_name'),
            "business_type": req_body.get('business_type'),
            "language_examples": req_body.get('language_examples')
        }

        # 10. Prepare and Return Success Response with standardized metadata
        processing_time_ms = int((time.time() - start_time) * 1000)
        success_payload = {
            "success": True,
            "type": "quick_draft",
            "task_data": task_data,
            "revision_context": revision_context,
            "llm_provider": provider,
            "llm_model": model,  # ADD: specific model used
            "processing_time_ms": processing_time_ms,  # ADD: processing time
            "extra_text": extra_text,
            "thinking_enabled": getattr(ai_service, "_last_thinking_enabled", False),
            "thinking_budget_tokens": getattr(ai_service, "_last_thinking_budget", None)
        }
        
        # 11. CRITICAL: Call back to API with results (callback mechanism)
        callback_url = req_body.get('callback_url')
        id = req_body.get('id')
        
        if callback_url and id:
            logger.info(f"🔗 CALLING CALLBACK: {callback_url}")
            logger.info(f"📊 Callback payload keys: {list(success_payload.keys())}")
            
            # Prepare callback payload with request metadata
            callback_payload = {
                "id": id,
                "request_type": "quick_draft",
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
        
        logger.info("get_quick_draft completed successfully.")
        status = "success"
        result = success_payload
        return https_fn.Response(
            json.dumps(success_payload, ensure_ascii=False).encode('utf-8'), 
            status=200, 
            mimetype="application/json; charset=utf-8"
        )

    except Exception as e:
        error = str(e)
        logger.error(f"Critical error in get_quick_draft: {e}", exc_info=True)
        # Return a generic server error response
        error_payload = {
            "success": False,
            "type": "quick_draft",
            "error": f"Internal server error: {e}",
            "task_data": None,
            "revision_context": None
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
                    "request_type": "quick_draft",
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
        # Log basic completion info
        completed_at = time.time()
        duration_ms = int((completed_at - start_time) * 1000)
        logger.info(f"get_quick_draft completed in {duration_ms}ms with status: {status}") 