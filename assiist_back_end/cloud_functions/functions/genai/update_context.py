import requests
import json
import time
import asyncio
import logging
import os
from datetime import datetime, timezone
from typing import Dict, Any, Optional

from firebase_functions import https_fn, options
from firebase_admin import initialize_app, firestore
from genai.services.ai_generation_service import get_ai_generation_service
from genai.shared import json_utils

# Initialize Firebase Admin SDK
import firebase_admin
if not firebase_admin._apps:
    initialize_app()

logger = logging.getLogger(__name__)
options.set_global_options(region="us-central1")

# --- Helper Functions ---

def generate_context_prompt(params):
    """Generate prompt for context analysis and updates."""
    # Extract parameters with defaults
    user_first_name = params.get('user_first_name', '')
    user_last_name = params.get('user_last_name', '')
    business_name = params.get('business_name', '')
    business_type = params.get('business_type', '')
    raw_note = params.get('raw_note', '')
    
    # Contact information
    contact_name = params.get('contact_name', '')
    addressed_as = params.get('addressed_as', '')
    
    # Current context information
    personal_details = params.get('personal_details', {})
    relationship_details = params.get('relationship_details', {})
    business_details = params.get('business_details', {})
    
    # Time-zone handling
    user_timezone = params.get('user_timezone', 'UTC')
    try:
        from zoneinfo import ZoneInfo
        tz = ZoneInfo(user_timezone)
    except Exception:
        tz = timezone.utc
        logger.warning(f"Unknown timezone {user_timezone}; defaulting to UTC in prompt")

    # Use user-local date for clarity in prompt
    today = datetime.now(tz).strftime('%A, %B %d, %Y at %I:%M %p %Z')

    user_message = f"""

================================
## IDENTITY & ROLE
================================

You are an expert assistant helping {user_first_name} {user_last_name} maintain and update contact information. Your task is to analyze the provided note content and determine what updates should be made to the contact's personal details, relationship details, and business details.

================================
## INPUT DATA
================================

<facts>

<user_information>
User's Name: {user_first_name} {user_last_name}
Business Name: {business_name}
Business Type: {business_type}
User ID: {params.get('user_id', '')}
</user_information>

<contact_information>
Contact Name: {contact_name}
Addressed As: {addressed_as}
</contact_information>

<date_information>
User Time Zone: {user_timezone}
Today's Date: {today}
</date_information>

<note_content>
{raw_note}
</note_content>

<current_context>
<personal_details>
{json.dumps(personal_details, indent=2)}
</personal_details>

<relationship_details>
{json.dumps(relationship_details, indent=2)}
</relationship_details>

<business_details>
{json.dumps(business_details, indent=2)}
</business_details>
</current_context>

</facts>

================================
## TASK INSTRUCTIONS
================================

Analyze the note content and determine what updates should be made to the contact's information. Focus on extracting:

1. **Personal Details Updates**: Information about family, occupation, recreation, dreams, or other personal information
2. **Relationship Details Updates**: Information about the relationship between {user_first_name} and this contact (only update for this specific user)
3. **Business Details Updates**: Information about business opportunities, developments, or other business-related context

================================
## OUTPUT FORMAT
================================

You must respond with a valid JSON object in the following format:

```json
{{
    "success": true,
    "context_updates": {{
        "personal_details_updates": {{
            "family": "Updated family information if mentioned",
            "occupation": "Updated occupation if mentioned",
            "recreation": "Updated recreation information if mentioned", 
            "dreams": "Updated dreams/goals if mentioned",
            "additional_info": "Any other personal information"
        }},
        "relationship_details_updates": {{
            "{params.get('user_id', '')}": "Updated relationship information between {user_first_name} and this contact"
        }},
        "business_details_updates": {{
            "opportunities": [
                {{
                    "opportunity_description": "Description of business opportunity",
                    "latest_development": "Latest development or status"
                }}
            ]
        }},
        "reason": "Brief explanation of the updates made"
    }},
    "llm_provider": "anthropic"
}}
```

================================
## IMPORTANT RULES
================================

1. **Only include fields that have actual updates** - omit sections where no new information is found
2. **Be conservative** - only update information that is clearly stated or strongly implied in the note
3. **Preserve existing information** - don't remove or contradict existing details unless clearly superseded
4. **For relationship details** - only update the entry for user_id {params.get('user_id', '')}
5. **For business opportunities** - preserve existing opportunities and add new ones, or update existing ones if clearly related
6. **Use clear, concise language** in updates
7. **If no updates are needed**, return: `{{"success": true, "context_updates": null, "reason": "No context updates needed based on note content"}}`

Analyze the note content now and provide the JSON response:
"""

    return user_message

def validate_inputs(data):
    """Validate required inputs for context update AI processing.
    
    Only validates fields needed for AI processing (NO database routing IDs).
    Database IDs (user_id, contact_id) are stored in Firestore, not needed for AI processing.
    """
    required_fields = ['raw_note']  # Only the note content is required for AI analysis
    missing_fields = [field for field in required_fields if not data.get(field)]
    
    if missing_fields:
        raise ValueError(f"Missing required fields: {', '.join(missing_fields)}")
    
    return True

@https_fn.on_request(
    timeout_sec=540,
    memory=options.MemoryOption.GB_2,
    region="us-central1",
    secrets=["ANTHROPIC_API_KEY", "GEMINI_API_KEY"]
)
def update_context(request: https_fn.Request) -> https_fn.Response:
    """
    HTTP Cloud Function to update contact context based on conversation history.
    """
    start_time = time.time()
    
    ai_service = get_ai_generation_service()
    
    # --- Webhook validation ---
    if request.method != "POST":
        logger.warning("Received non-POST request")
        return https_fn.Response(
            json.dumps({"success": False, "error": "Only POST method allowed"}),
            status=405,
            headers={"Content-Type": "application/json"}
        )
    
    try:
        logger.info("🔄 update_context Cloud Function started")
        
        # Parse request data
        data = request.get_json()
        if not data:
            raise ValueError("No JSON data provided")
        
        logger.info(f"📋 Request data keys: {list(data.keys())}")
        logger.info(f"📝 Received update_context request")
        
        # Extract required fields for tracking
        callback_url = data.get('callback_url')
        id = data.get('id')
        user_id = data.get('user_id')  # Needed for relationship_details key
        raw_note = data.get('raw_note', '')
        
        # Validate inputs
        validate_inputs(data)
        
        # Generate prompt
        logger.info("Creating context analysis prompt...")
        prompt = generate_context_prompt(data)
        
        # Prepare messages for AI service
        anthropic_messages = [{"role": "user", "content": prompt}]
        gemini_prompt_text = prompt
        
        # Call AI service
        logger.info("🧠 Calling AI service for context analysis...")
        
        response_text, provider, error_message = asyncio.run(ai_service.execute_llm_call(
            anthropic_messages=anthropic_messages,
            gemini_prompt_text=gemini_prompt_text,
            temperature=0.1,
            max_tokens=2000,
            gemini_response_mime_type="application/json"
        ))
        
        model = ai_service._anthropic_model if provider == "anthropic" else ai_service._gemini_model_name
        llm_response = response_text
        
        if error_message:
            logger.error(f"❌ AI service error: {error_message}")
            raise Exception(f"AI generation failed: {error_message}")
        
        if not response_text:
            logger.error("AI generation returned no text content.")
            raise Exception("AI generation returned no content.")
        
        logger.info(f"🤖 AI generation successful using {provider} with model: {model}")
        
        # Extract JSON from AI Response
        extraction_result = json_utils.extract_json(response_text)
        parsed_json_str = extraction_result.get('extracted_json')
        extra_text = extraction_result.get('extra_text')
        
        if not parsed_json_str:
            logger.error(f"Failed to extract valid JSON from {provider} response.")
            logger.debug(f"Raw response text from {provider}: {response_text}")
            raise Exception("AI response format error: Could not parse JSON.")
        
        try:
            result = json.loads(parsed_json_str)
        except json.JSONDecodeError as e:
            logger.error(f"Error decoding extracted JSON: {e}")
            logger.debug(f"Extracted JSON string: {parsed_json_str}")
            raise Exception("AI response format error: Invalid JSON structure.") from e
        
        # Validate response structure
        if not isinstance(result, dict):
            raise Exception("Response is not a valid JSON object")
        
        if not result.get('success'):
            error_msg = result.get('error', 'Unknown error from LLM')
            logger.error(f"❌ LLM processing failed: {error_msg}")
            raise Exception(error_msg)
        
        # Prepare success response with standardized metadata
        processing_time_ms = int((time.time() - start_time) * 1000)
        
        success_payload = {
            "success": True,
            "type": "update_context",
            "context_updates": result.get('context_updates'),  # Clean AI results only
            "llm_provider": provider,
            "llm_model": model,  # ADD: specific model used
            "processing_time_ms": processing_time_ms,  # ADD: processing time in ms
            "original_note": data.get('raw_note', ''),
            "extra_text": extra_text,
            "thinking_enabled": getattr(ai_service, "_last_thinking_enabled", False),
            "thinking_budget_tokens": getattr(ai_service, "_last_thinking_budget", None)
        }
        
        logger.info(f"✅ Context analysis completed successfully in {processing_time_ms/1000:.2f}s")
        logger.info(f"📊 Updates found: {bool(result.get('context_updates'))}")
        
        # CRITICAL: Call back to API with results (callback mechanism)
        if callback_url and id:
            logger.info(f"🔗 CALLING CALLBACK: {callback_url}")
            logger.info(f"📊 Callback payload keys: {list(success_payload.keys())}")
            
            callback_payload = {
                "id": id,
                "request_type": "update_context",
                "callback_url": callback_url,  # ✅ Include the callback URL used
                **success_payload  # Include all AI results
            }
            
            try:
                callback_response = requests.post(
                    callback_url,
                    headers={"Content-Type": "application/json"},
                    json=callback_payload,
                    timeout=30
                )
                
                if callback_response.status_code == 200:
                    logger.info(f"✅ Successfully called back to API for request {id}")
                else:
                    logger.error(f"❌ Callback failed: {callback_response.status_code} - {callback_response.text}")
                    
            except Exception as callback_error:
                logger.error(f"❌ Error calling back to API: {callback_error}")
                # Don't fail the entire function - just log the error
        else:
            logger.warning("⚠️ No callback_url or id provided - skipping callback")
        
        logger.info("update_context completed successfully.")
        status = "success"
        result = success_payload
        return https_fn.Response(
            json.dumps(success_payload),
            status=200,
            headers={"Content-Type": "application/json"}
        )
        
    except Exception as e:
        error = str(e)
        logger.error(f"❌ Critical error in update_context: {e}", exc_info=True)
        
        error_payload = {
            "success": False,
            "type": "update_context",
            "error": f"Internal server error: {e}"
        }
        
        # CRITICAL: Call back to API with error results if possible
        callback_url = None
        id = None
        try:
            if request.get_json():
                data = request.get_json()
                callback_url = data.get('callback_url')
                id = data.get('id')
                
            if callback_url and id:
                logger.info(f"🔗 CALLING ERROR CALLBACK: {callback_url}")
                
                callback_payload = {
                    "id": id,
                    "request_type": "update_context",
                    "callback_url": callback_url,  # ✅ Include callback URL in error callback too
                    **error_payload
                }
                
                try:
                    response = requests.post(
                        callback_url,
                        headers={"Content-Type": "application/json"},
                        json=callback_payload,
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
            json.dumps(error_payload),
            status=500,
            headers={"Content-Type": "application/json"}
        )
    finally:
        # Log completion info
        completed_at = time.time()
        duration_ms = int((completed_at - start_time) * 1000)
        logger.info(f"update_context completed in {duration_ms}ms with status: {status}") 