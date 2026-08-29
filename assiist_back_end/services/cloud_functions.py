import json
import logging
import os
from typing import Dict, Any, Optional
import httpx

logger = logging.getLogger(__name__)

async def call_function(
    function_name: str,
    data: Dict[str, Any],
    region: str = "us-central1",
    project_id: Optional[str] = None
) -> Dict[str, Any]:
    """Call a Firebase Cloud Function.
    
    Args:
        function_name: The name of the function to call
        data: The data to send to the function
        region: The region where the function is deployed
        project_id: The Google Cloud project ID (optional, uses env var if not provided)
        
    Returns:
        The response from the function as a dictionary
    """
    # Get project ID from environment if not provided
    if not project_id:
        # Try FIREBASE_PROJECT_ID first (from user's .env), then GOOGLE_CLOUD_PROJECT, then default
        project_id = (
            os.environ.get("FIREBASE_PROJECT_ID") or 
            os.environ.get("GOOGLE_CLOUD_PROJECT") or 
            "assiist-app"  # Default fallback
        )
        
        if not project_id:
            raise ValueError("Project ID not provided and not found in environment")
    
    logger.info(f"📋 Using project ID: {project_id}")
    
    # Build URL to the function
    function_url = f"https://{region}-{project_id}.cloudfunctions.net/{function_name}"
    
    logger.info(f"🔗 Calling cloud function: {function_url}")
    logger.info(f"📊 Request payload keys: {list(data.keys())}")
    
    # Call the function
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                function_url,
                json=data,  # Send data directly without wrapper
                timeout=540.0  # 3-minute timeout for heavy AI operations
            )
            
            # Log response details
            logger.info(f"📡 Response status: {response.status_code}")
            logger.info(f"📊 Response headers: {dict(response.headers)}")
            
            # Check if response is successful
            if response.status_code >= 400:
                logger.error(f"❌ Cloud function returned error status: {response.status_code}")
                response_text = response.text
                logger.error(f"❌ Error response body: {response_text[:500]}{'...' if len(response_text) > 500 else ''}")
                
                return {
                    "success": False, 
                    "error": f"HTTP {response.status_code}: {response_text[:200]}",
                    "status_code": response.status_code
                }
            
            # Try to parse JSON response
            try:
                result = response.json()
                logger.info(f"✅ Cloud function response parsed successfully")
                logger.info(f"📊 Response keys: {list(result.keys()) if isinstance(result, dict) else 'Not a dict'}")
                
                # Log success/error indicators if present
                if isinstance(result, dict):
                    if "success" in result:
                        logger.info(f"🎯 Success indicator: {result['success']}")
                    if "error" in result:
                        logger.warning(f"⚠️ Error in response: {result['error']}")
                
                return result
                
            except json.JSONDecodeError as json_err:
                logger.error(f"❌ Failed to parse JSON response: {json_err}")
                response_text = response.text
                logger.error(f"❌ Raw response: {response_text[:500]}{'...' if len(response_text) > 500 else ''}")
                
                return {
                    "success": False, 
                    "error": f"Invalid JSON response: {str(json_err)}",
                    "raw_response": response_text[:200]
                }
            
        except httpx.TimeoutException as e:
            logger.error(f"⏰ Timeout calling cloud function {function_name}: {str(e)}")
            return {"success": False, "error": f"Timeout after 540s: {str(e)}"}
            
        except httpx.ConnectError as e:
            logger.error(f"🔌 Connection error calling cloud function {function_name}: {str(e)}")
            return {"success": False, "error": f"Connection failed: {str(e)}"}
            
        except httpx.RequestError as e:
            logger.error(f"📡 Request error calling cloud function {function_name}: {str(e)}")
            return {"success": False, "error": f"Request failed: {str(e)}"}
            
        except Exception as e:
            logger.error(f"❌ Unexpected error calling cloud function {function_name}: {str(e)}")
            return {"success": False, "error": f"Unexpected error: {str(e)}"} 