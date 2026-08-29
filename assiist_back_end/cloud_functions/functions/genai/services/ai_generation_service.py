import uuid
from typing import Dict, Any, Optional, Tuple, List
import asyncio
import os
import time
import random
import json
import logging

# Load environment variables from a .env file if present (for local development/emulator)
# This happens BEFORE we start fetching env vars so they are available globally.
try:
    from dotenv import load_dotenv

    # Attempt to locate the nearest .env file up the directory tree
    _current_dir = os.path.dirname(os.path.abspath(__file__))
    _candidate_dirs = [
        _current_dir,
        os.path.abspath(os.path.join(_current_dir, "..")),  # services/
        os.path.abspath(os.path.join(_current_dir, "../..")),  # genai/
        os.path.abspath(os.path.join(_current_dir, "../../..")),  # functions/
        os.path.abspath(os.path.join(_current_dir, "../../../..")),  # cloud_functions/
    ]

    for _dir in _candidate_dirs:
        env_path = os.path.join(_dir, ".env")
        if os.path.isfile(env_path):
            load_dotenv(dotenv_path=env_path, override=False)
            logging.getLogger(__name__).info(f"Loaded environment variables from {env_path}")
            break
except Exception as _e:
    # Swallow any errors – not fatal in production where .env may not exist
    logging.getLogger(__name__).debug(f"dotenv load skipped/unavailable: {_e}")

# Import LLM clients
import google.generativeai as genai
from anthropic import Anthropic, AsyncAnthropic, APIStatusError, RateLimitError, APIConnectionError, AnthropicError
import google.ai.generativelanguage as glm
from openai import AsyncOpenAI

# No longer using SecretParam - service reads environment variables directly

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants for retry logic
DEFAULT_MAX_RETRIES = 3
DEFAULT_INITIAL_DELAY_MS = 1000 # 1 second

# --- Environment Variables Helper ---
# Define parameterized configuration for thinking mode
try:
    from firebase_functions.params import StringParam, IntParam
    ENABLE_THINKING = StringParam("ENABLE_THINKING", default="false")
    THINKING_BUDGET_TOKENS = IntParam("THINKING_BUDGET_TOKENS", default=8000)
    params_available = True
    print(f"[DEBUG] Firebase params available: StringParam and IntParam imported successfully")
except ImportError:
    params_available = False
    print(f"[DEBUG] Firebase params not available - parameterized config disabled")

def _sanitize_api_keys() -> None:
    """Sanitize all API key environment variables by stripping whitespace."""
    for env_var in list(os.environ.keys()):
        if env_var.endswith('_API_KEY'):
            value = os.environ[env_var]
            if value:
                cleaned = value.strip()
                if cleaned != value:
                    logger.info(f"Sanitized {env_var} environment variable (removed whitespace)")
                os.environ[env_var] = cleaned

def _get_env_var(name: str, default: Optional[str] = None) -> Optional[str]:
    """Get env var, falling back to Firebase Functions parameterized config."""
    val = os.environ.get(name)
    print(f"[DEBUG] _get_env_var({name}): os.environ value = '{val}'")
    
    # Use parameterized configuration as fallback
    if val is None and params_available:
        try:
            if name == "ENABLE_THINKING":
                val = ENABLE_THINKING.value
                print(f"[DEBUG] _get_env_var({name}): Firebase param value = '{val}'")
            elif name == "THINKING_BUDGET_TOKENS":
                val = str(THINKING_BUDGET_TOKENS.value)
                print(f"[DEBUG] _get_env_var({name}): Firebase param value = '{val}'")
        except Exception as e:
            print(f"[DEBUG] _get_env_var({name}): Firebase param access failed: {e}")
    
    if val is None:
        val = default
        print(f"[DEBUG] _get_env_var({name}): using default = '{val}'")
    
    # Strip whitespace/newlines from API keys to prevent header issues
    if val and name.endswith('_API_KEY'):
        val = val.strip()
        print(f"[DEBUG] _get_env_var({name}): sanitized API key")
    print(f"[DEBUG] _get_env_var({name}): final value = '{val}'")
    return val

class AIGenerationService:
    """Handles interaction with AI models (Anthropic, Gemini, OpenAI) for task/draft generation."""

    def __init__(self):
        logger.debug("AIGenerationService.__init__() called")
        
        # Sanitize all API keys on initialization
        _sanitize_api_keys()
        
        self._anthropic_client = None
        self._gemini_client = None
        self._openai_client = None
        
        # Debug: Log available environment variables
        env_keys = [k for k in os.environ.keys() if 'API_KEY' in k or 'ANTHROPIC' in k or 'GEMINI' in k or 'OPENAI' in k]
        logger.debug(f"Available env vars with API_KEY/ANTHROPIC/GEMINI/OPENAI: {env_keys}")
        
        # Cache model names on init
        self._anthropic_model = _get_env_var('ANTHROPIC_MODEL', 'claude-sonnet-4-20250514')
        self._gemini_model_name = _get_env_var('GEMINI_MODEL', 'gemini-2.5-pro-preview-06-05')
        self._openai_model = _get_env_var('OPENAI_MODEL', 'gpt-4o')
        
        # Configure provider delegation - support multiple fallbacks
        self._primary_provider = _get_env_var('PRIMARY_PROVIDER', 'anthropic').lower()
        fallback_providers_str = _get_env_var('FALLBACK_PROVIDERS', 'openai,gemini')
        self._fallback_providers = [p.strip().lower() for p in fallback_providers_str.split(',') if p.strip()]
        
        # Validate provider names
        valid_providers = ['anthropic', 'gemini', 'openai']
        if self._primary_provider not in valid_providers:
            logger.warning(f"Invalid PRIMARY_PROVIDER '{self._primary_provider}', defaulting to 'anthropic'")
            self._primary_provider = 'anthropic'
        
        # Filter out invalid fallback providers and remove primary from fallbacks
        self._fallback_providers = [p for p in self._fallback_providers 
                                   if p in valid_providers and p != self._primary_provider]
        
        logger.info(f"AIGenerationService initialized. Primary: {self._primary_provider}, Fallbacks: {self._fallback_providers}")
        logger.info(f"Models - Anthropic: {self._anthropic_model}, Gemini: {self._gemini_model_name}, OpenAI: {self._openai_model}")

        # Track last thinking mode usage
        self._last_thinking_enabled: bool = False
        self._last_thinking_budget: Optional[int] = None

    def _validate_client_initialization(self) -> Dict[str, bool]:
        """Validate that AI clients can be properly initialized."""
        validation_results = {
            'anthropic_available': False,
            'gemini_available': False,
            'openai_available': False,
            'anthropic_error': None,
            'gemini_error': None,
            'openai_error': None
        }
        
        # Test Anthropic client
        try:
            anthropic_client = self._get_anthropic_client()
            if anthropic_client:
                validation_results['anthropic_available'] = True
            else:
                validation_results['anthropic_error'] = "Client initialization returned None"
        except Exception as e:
            validation_results['anthropic_error'] = str(e)
        
        # Test Gemini client
        try:
            gemini_client = self._get_gemini_client()
            if gemini_client:
                validation_results['gemini_available'] = True
            else:
                validation_results['gemini_error'] = "Client initialization returned None"
        except Exception as e:
            validation_results['gemini_error'] = str(e)
        
        # Test OpenAI client
        try:
            openai_client = self._get_openai_client()
            if openai_client:
                validation_results['openai_available'] = True
            else:
                validation_results['openai_error'] = "Client initialization returned None"
        except Exception as e:
            validation_results['openai_error'] = str(e)
        
        logger.info(f"Client validation results: {validation_results}")
        return validation_results

    def _get_anthropic_client(self) -> Optional[AsyncAnthropic]:
        logger.debug("_get_anthropic_client() called")
        if self._anthropic_client is None:
            api_key = _get_env_var('ANTHROPIC_API_KEY')
            logger.debug(f"ANTHROPIC_API_KEY from environment: {'present' if api_key else 'missing'} (length: {len(api_key) if api_key else 0})")
            if api_key:
                try:
                    # Use AsyncAnthropic for proper async support
                    self._anthropic_client = AsyncAnthropic(api_key=api_key)
                    logger.debug("AsyncAnthropic client created successfully")
                except Exception as e:
                    logger.error(f"Failed to create AsyncAnthropic client: {e}")
            else:
                logger.error("Cannot create Anthropic client: ANTHROPIC_API_KEY not found in environment.")
        else:
            logger.debug("Using existing AsyncAnthropic client")
        return self._anthropic_client

    def _get_gemini_client(self) -> Optional[genai.GenerativeModel]:
        logger.debug("_get_gemini_client() called")
        if self._gemini_client is None:
            api_key = _get_env_var('GEMINI_API_KEY')
            logger.debug(f"GEMINI_API_KEY from environment: {'present' if api_key else 'missing'} (length: {len(api_key) if api_key else 0})")
            if api_key:
                try:
                    # Configure Gemini API key
                    genai.configure(api_key=api_key)
                    
                    # Simplified model initialization
                    self._gemini_client = genai.GenerativeModel(self._gemini_model_name)
                    logger.debug(f"Gemini client created for model: {self._gemini_model_name}")
                except Exception as e:
                    logger.error(f"Failed to create/configure Gemini client: {e}")
            else:
                logger.debug("GEMINI_API_KEY is not set - Gemini integration is disabled")
        else:
            logger.debug("Using existing Gemini client")
        return self._gemini_client

    def _get_openai_client(self) -> Optional[AsyncOpenAI]:
        logger.debug("_get_openai_client() called")
        if self._openai_client is None:
            api_key = _get_env_var('OPENAI_API_KEY')
            logger.debug(f"OPENAI_API_KEY from environment: {'present' if api_key else 'missing'} (length: {len(api_key) if api_key else 0})")
            if api_key:
                try:
                    # Use AsyncOpenAI for proper async support
                    self._openai_client = AsyncOpenAI(api_key=api_key)
                    logger.debug("AsyncOpenAI client created successfully")
                except Exception as e:
                    logger.error(f"Failed to create AsyncOpenAI client: {e}")
            else:
                logger.error("Cannot create OpenAI client: OPENAI_API_KEY not found in environment.")
        else:
            logger.debug("Using existing AsyncOpenAI client")
        return self._openai_client

    async def _handle_gemini_safety_retry(self, original_prompt: str, client: genai.GenerativeModel, generation_config: Any) -> Any:
        """Retry Gemini request with safety-filter-friendly prompt modifications."""
        
        # Common prompt modifications to avoid safety blocks
        safety_modifications = [
            # Modification 1: Add business context
            f"For business communication purposes: {original_prompt}",
            
            # Modification 2: Emphasize professional context
            f"In a professional business setting: {original_prompt}",
            
            # Modification 3: Simplify language
            original_prompt.replace("analyze", "review").replace("generate", "create"),
        ]
        
        for i, modified_prompt in enumerate(safety_modifications):
            try:
                logger.info(f"Gemini safety retry attempt {i+1}: Trying modified prompt")
                response = await client.generate_content_async(
                    contents=modified_prompt,
                    generation_config=generation_config
                )
                
                # Check if this retry succeeded
                if response.candidates and response.candidates[0].content:
                    candidate = response.candidates[0]
                    if hasattr(candidate.content, 'parts') and candidate.content.parts:
                        if hasattr(candidate.content.parts[0], 'text'):
                            text = candidate.content.parts[0].text.strip()
                            if text:
                                logger.info(f"Gemini safety retry {i+1} succeeded")
                                return response
                
            except Exception as e:
                logger.warning(f"Gemini safety retry {i+1} failed: {e}")
                continue
        
        # All retries failed
        logger.error("All Gemini safety filter retries failed")
        return None

    async def _make_llm_request_with_retry(
        self,
        client_provider_func: callable,
        request_func: callable,
        provider_name: str, # Added for logging clarity
        max_retries: int = DEFAULT_MAX_RETRIES,
        initial_delay_ms: int = DEFAULT_INITIAL_DELAY_MS
    ) -> Any:
        """
        Makes a request to an LLM API with retry logic for specific errors.
        """
        client = client_provider_func()
        if not client:
            raise ConnectionError(f"Failed to initialize {provider_name} client.")

        last_exception = None
        for attempt in range(max_retries):
            try:
                logger.info(f"{provider_name} API Call - Attempt {attempt + 1}/{max_retries}...")
                result = await request_func(client)
                logger.info(f"{provider_name} API Call - Attempt {attempt + 1} successful.")
                return result # Success
            # --- Retryable Errors ---
            # Anthropic specific retryable errors
            except (RateLimitError, APIStatusError, APIConnectionError) as e:
                last_exception = e
                logger.warning(f"{provider_name} API Call - Attempt {attempt + 1} failed with retryable error: {type(e).__name__} - {e}. Retrying...")
            # Gemini specific retryable errors (Add specific Gemini error types if known, e.g., related to resource exhaustion or temporary unavailability)
            # except GeminiRetryableError as e: ...
            # General potential retryable errors
            except (asyncio.TimeoutError) as e: # Timeout on our side waiting for response
                last_exception = e
                logger.warning(f"{provider_name} API Call - Attempt {attempt + 1} timed out ({type(e).__name__}). Retrying...")
            except Exception as e:
                # Check if it's a potentially retryable service error (e.g., 5xx HTTP codes if using REST)
                # This requires inspecting the error object, which varies by library
                # Example placeholder check:
                is_retryable_service_error = False
                if hasattr(e, 'status_code') and isinstance(e.status_code, int) and e.status_code >= 500:
                     is_retryable_service_error = True
                elif "service unavailable" in str(e).lower(): # Example string check
                     is_retryable_service_error = True

                if is_retryable_service_error:
                    last_exception = e
                    logger.warning(f"{provider_name} API Call - Attempt {attempt + 1} failed with potentially retryable service error: {type(e).__name__} - {e}. Retrying...")
                else:
                    # --- Non-Retryable Errors ---
                    last_exception = e
                    logger.error(f"{provider_name} API Call - Attempt {attempt + 1} failed with non-retryable error: {type(e).__name__} - {e}.")
                    break # Stop retrying for non-retryable errors

            # --- Backoff Logic ---
            if attempt == max_retries - 1:
                logger.error(f"{provider_name} API Call failed after {max_retries} attempts.")
                break # Max retries reached

            backoff_time_ms = initial_delay_ms * (2 ** attempt)
            jitter_ms = random.uniform(0, 0.3 * backoff_time_ms)
            sleep_time_sec = (backoff_time_ms + jitter_ms) / 1000.0
            logger.info(f"Sleeping for {sleep_time_sec:.2f} seconds before next retry.")
            await asyncio.sleep(sleep_time_sec)

        raise last_exception or Exception(f"{provider_name} request failed after multiple retries or due to a non-retryable error.")

    async def _call_anthropic(
        self,
        messages: list,
        max_tokens: int,
        temperature: float,
        system_prompt: Optional[str] = None,
        thinking_config: Optional[Dict[str, Any]] = None
        ) -> Dict[str, Any]:
        """Makes a call to the Anthropic API."""
        async def request(client: AsyncAnthropic):
            logger.info(f"Calling Anthropic model: {self._anthropic_model}")
            
            try:
                # Automatically adjust temperature when thinking is enabled
                actual_temperature = temperature
                if thinking_config:
                    actual_temperature = 1.0  # Required by Anthropic when thinking is enabled
                    if temperature != 1.0:
                        logger.info(f"Temperature adjusted from {temperature} to 1.0 (required for thinking)")
                
                # Automatically adjust max_tokens when thinking is enabled
                actual_max_tokens = max_tokens
                if thinking_config:
                    thinking_budget = thinking_config.get('budget_tokens', 0)
                    if max_tokens <= thinking_budget:
                        # Set max_tokens to be at least 1000 tokens more than thinking budget
                        actual_max_tokens = thinking_budget + 1000
                        logger.info(f"max_tokens adjusted from {max_tokens} to {actual_max_tokens} (must be > thinking budget of {thinking_budget})")
                
                # Create call parameters
                call_params = {
                    "model": self._anthropic_model,
                    "max_tokens": actual_max_tokens,
                    "temperature": actual_temperature,
                    "messages": messages
                }
                
                # Only add system if provided and not empty
                if system_prompt and system_prompt.strip():
                    call_params["system"] = system_prompt
                
                # Add thinking configuration if provided
                if thinking_config:
                    call_params["thinking"] = thinking_config
                    logger.info(f"Thinking enabled with config: {thinking_config}")
                
                # Direct async call - AsyncAnthropic supports this natively
                response = await client.messages.create(**call_params)
                
                logger.debug(f"Anthropic Raw Response: {response}")
                return response.model_dump()
                
            except Exception as e:
                logger.error(f"Error during Anthropic API call: {e}", exc_info=True)
                raise

        # Pass provider name for logging
        return await self._make_llm_request_with_retry(self._get_anthropic_client, request, "Anthropic")

    async def _call_gemini(
        self,
        prompt: str,
        temperature: float,
        max_tokens: int,
        # Add other relevant Gemini config params if needed (e.g., stop_sequences, top_p, top_k)
        response_mime_type: Optional[str] = None # e.g., "application/json"
        ) -> Any: # Return type depends on how you process the Gemini response
        """Makes a call to the Gemini API."""
        async def request(client: genai.GenerativeModel):
            logger.info(f"Calling Gemini model: {client.model_name}")

            # Construct GenerationConfig dynamically
            config_params = {
                 "temperature": temperature,
                 "max_output_tokens": max_tokens,
            }
            # Only add mime type if explicitly requested
            # NOTE: Forcing JSON might make Gemini behave differently or error if it can't comply
            if response_mime_type:
                 # Check if response_mime_type is supported by the model/SDK version
                 try:
                      # Use the glm type for safety if available
                      config_params["response_mime_type"] = response_mime_type
                      logger.info(f"Requesting Gemini response mime type: {response_mime_type}")
                 except (AttributeError, TypeError):
                      logger.warning(f"response_mime_type specified but may not be supported, omitting from config.")


            generation_config = genai.types.GenerationConfig(**config_params)

            # Gemini SDK's generate_content_async
            try:
                 response = await client.generate_content_async(
                     contents=prompt, # Assuming prompt is correctly formatted string
                     generation_config=generation_config,
                     request_options={ # Pass request options like timeout again if needed/possible
                         "timeout": int(_get_env_var('GEMINI_REQUEST_TIMEOUT', '120'))
                     }
                 )
                 logger.debug(f"Gemini Raw Response: {response}")
                 return response # Return the Gemini response object
            except Exception as e:
                 logger.error(f"Error during Gemini generate_content_async call: {e}", exc_info=True)
                 raise # Re-raise to be caught by retry logic

        # Pass provider name for logging
        # Note: Gemini might have its own retry mechanism; this adds another layer.
        return await self._make_llm_request_with_retry(self._get_gemini_client, request, "Gemini")

    async def _call_openai(
        self,
        messages: list,
        max_tokens: int,
        temperature: float,
        system_prompt: Optional[str] = None,
        thinking_config: Optional[Dict[str, Any]] = None
        ) -> Dict[str, Any]:
        """Makes a call to the OpenAI API."""
        async def request(client: AsyncOpenAI):
            logger.info(f"Calling OpenAI model: {self._openai_model}")
            
            try:
                # Create call parameters
                call_params = {
                    "model": self._openai_model,
                    "max_tokens": max_tokens,
                    "temperature": temperature,
                    "messages": messages
                }
                
                # OpenAI handles system prompts differently - add as system message if provided
                if system_prompt and system_prompt.strip():
                    # Insert system message at the beginning
                    call_params["messages"] = [{"role": "system", "content": system_prompt}] + messages
                
                # Note: OpenAI doesn't support extended thinking like Anthropic
                if thinking_config:
                    logger.info(f"Thinking config provided but OpenAI doesn't support extended thinking - ignoring")
                
                # Direct async call - AsyncOpenAI supports this natively
                response = await client.chat.completions.create(**call_params)
                
                logger.debug(f"OpenAI Raw Response: {response}")
                return response.model_dump()
                
            except Exception as e:
                logger.error(f"Error during OpenAI API call: {e}", exc_info=True)
                raise

        # Pass provider name for logging
        return await self._make_llm_request_with_retry(self._get_openai_client, request, "OpenAI")

    # --- Refactored Public Method ---

    async def execute_llm_call(
        self,
        anthropic_messages: List[Dict[str, Any]],
        gemini_prompt_text: str,
        anthropic_system: Optional[str] = None,
        # Allow overriding model parameters per call if needed
        max_tokens: int = 4096,
        temperature: float = 0.1,
        gemini_response_mime_type: Optional[str] = None, # Optional: force Gemini JSON
        thinking_config: Optional[Dict[str, Any]] = None,  # Optional: enable thinking for Anthropic
        openai_response_format: Optional[str] = None  # Optional: specify OpenAI response format (e.g., "json_object")
    ) -> Tuple[Optional[str], Optional[str], Optional[str]]:
        """
        Executes an LLM call using configurable primary provider with flexible fallback to other providers.
        Accepts pre-formatted prompts.

        Args:
            anthropic_messages: List of messages formatted for Anthropic API.
            gemini_prompt_text: Single string prompt formatted for Gemini API (also used for OpenAI if needed).
            anthropic_system: Optional system prompt string for Anthropic.
            max_tokens: Maximum tokens for the LLM response.
            temperature: Temperature setting for the LLM.
            gemini_response_mime_type: Optional: Request Gemini response as JSON.
            thinking_config: Optional: Enable thinking for Anthropic (e.g., {"type": "enabled", "budget_tokens": 10000}).
            openai_response_format: Optional: OpenAI response format ("json_object" for JSON mode).

        Returns:
            A tuple containing:
            (response_text: Optional[str], provider: Optional[str], error_message: Optional[str])
            - response_text: The raw text content from the successful LLM response.
            - provider: 'anthropic', 'gemini', or 'openai'.
            - error_message: Description of the error if all providers fail.
        """
        # ---------------------------------------------------------------
        # Auto-enable Anthropic thinking mode from environment variables
        # if caller hasn't provided a thinking_config.
        # ---------------------------------------------------------------
        if thinking_config is None:
            enable_thinking_env = _get_env_var('ENABLE_THINKING', 'true').lower() in ('true', '1', 'yes', 'on')
            # Debug: Show what we're actually getting
            raw_enable = _get_env_var('ENABLE_THINKING', 'true')
            raw_budget = _get_env_var('THINKING_BUDGET_TOKENS', '8000')
            print(f"[DEBUG] Raw ENABLE_THINKING value: '{raw_enable}'")
            print(f"[DEBUG] Raw THINKING_BUDGET_TOKENS value: '{raw_budget}'")
            print(f"[DEBUG] enable_thinking_env boolean: {enable_thinking_env}")
            if enable_thinking_env:
                try:
                    budget_tokens_env = int(_get_env_var('THINKING_BUDGET_TOKENS', '8000'))
                except ValueError:
                    budget_tokens_env = 8000  # Fallback to default if env var is not an int
                thinking_config = {
                    "type": "enabled",
                    "budget_tokens": budget_tokens_env
                }
                logger.info(f"Anthropic thinking mode enabled via ENV with budget_tokens={budget_tokens_env}")
                # Also emit a print so that it always appears in Cloud Run logs
                print(f"[AIService] Anthropic thinking mode ENABLED (budget_tokens={budget_tokens_env})")
            else:
                print(f"[DEBUG] Thinking mode NOT enabled - enable_thinking_env={enable_thinking_env}")
        # ---------------------------------------------------------------
        # Persist the thinking mode state for callers to reference later
        self._last_thinking_enabled = bool(thinking_config and thinking_config.get('type') == 'enabled')
        self._last_thinking_budget = thinking_config.get('budget_tokens') if self._last_thinking_enabled else None
        # ---------------------------------------------------------------
        
        # Create ordered list of providers to try (primary + fallbacks)
        providers_to_try = [self._primary_provider] + self._fallback_providers
        errors = {}
        
        # Try each provider in order
        for i, provider in enumerate(providers_to_try):
            is_primary = (i == 0)
            try:
                logger.info(f"Attempting LLM call with {provider.title()} ({'primary' if is_primary else 'fallback'})...")
                
                # Validate provider client can be created
                client = None
                if provider == 'anthropic':
                    client = self._get_anthropic_client()
                elif provider == 'gemini':
                    client = self._get_gemini_client()
                elif provider == 'openai':
                    client = self._get_openai_client()
                
                if not client:
                    raise ConnectionError(f"{provider.title()} API Key/Client not configured.")

                # Call the appropriate provider
                if provider == 'anthropic':
                    response_dict = await self._call_anthropic(
                        messages=anthropic_messages,
                        max_tokens=max_tokens,
                        temperature=temperature,
                        system_prompt=anthropic_system,
                        thinking_config=thinking_config
                    )
                    
                    # Extract text from Anthropic response
                    response_text = None
                    if hasattr(response_dict, 'content') and isinstance(response_dict.content, list):
                        for item in response_dict.content:
                            if hasattr(item, 'text'):
                                response_text = item.text.strip()
                                break
                    elif isinstance(response_dict.get('content'), list):
                        for item in response_dict['content']:
                            if item.get('type') == 'text':
                                response_text = item.get('text', '').strip()
                                break
                    elif 'completion' in response_dict:
                        response_text = response_dict.get('completion', '').strip()
                        
                elif provider == 'openai':
                    response_dict = await self._call_openai(
                        messages=anthropic_messages,
                        max_tokens=max_tokens,
                        temperature=temperature,
                        system_prompt=anthropic_system,
                        thinking_config=thinking_config
                    )
                    
                    # Extract text from OpenAI response
                    response_text = None
                    if 'choices' in response_dict and response_dict['choices']:
                        choice = response_dict['choices'][0]
                        if 'message' in choice and 'content' in choice['message']:
                            response_text = choice['message']['content'].strip()
                            
                elif provider == 'gemini':
                    gemini_response = await self._call_gemini(
                        prompt=gemini_prompt_text,
                        temperature=temperature,
                        max_tokens=max_tokens,
                        response_mime_type=gemini_response_mime_type
                    )
                    
                    # Extract text from Gemini response (special handling)
                    response_text = None
                    finish_reason = None
                    
                    if hasattr(gemini_response, 'candidates') and gemini_response.candidates:
                        candidate = gemini_response.candidates[0]
                        finish_reason = getattr(candidate, 'finish_reason', None)
                        
                        # Handle safety filter blocks with retry
                        if finish_reason == 2:  # SAFETY block
                            logger.warning("Gemini response blocked by safety filters, attempting retry")
                            
                            config_params = {
                                "temperature": temperature,
                                "max_output_tokens": max_tokens,
                            }
                            if gemini_response_mime_type:
                                config_params["response_mime_type"] = gemini_response_mime_type
                            generation_config = genai.types.GenerationConfig(**config_params)
                            
                            retry_response = await self._handle_gemini_safety_retry(
                                gemini_prompt_text, 
                                self._get_gemini_client(),
                                generation_config
                            )
                            
                            if retry_response:
                                gemini_response = retry_response
                                candidate = gemini_response.candidates[0]
                                finish_reason = getattr(candidate, 'finish_reason', None)
                                logger.info("Gemini safety filter retry succeeded")
                            else:
                                raise Exception("Gemini content blocked by safety filters and retries failed")
                        
                        # Extract text from response
                        if hasattr(candidate, 'content') and candidate.content:
                            if hasattr(candidate.content, 'parts') and candidate.content.parts:
                                part = candidate.content.parts[0]
                                if hasattr(part, 'text'):
                                    response_text = part.text.strip()
                
                # Check if we got a response
                if response_text:
                    logger.info(f"Successfully received response from {provider.title()}.")
                    return response_text, provider, None
                else:
                    raise Exception(f"{provider.title()} response missing text content")

            except Exception as e:
                error_msg = f"{type(e).__name__}: {str(e)}"
                errors[provider] = error_msg
                logger.error(f"{provider.title()} API call failed: {error_msg}")
                
                # If this was the last provider, we'll fall through to final error handling
                if i < len(providers_to_try) - 1:
                    logger.warning(f"{provider.title()} failed, trying next provider...")
                    continue

        # All providers failed
        error_details = ", ".join([f"{provider}: {error}" for provider, error in errors.items()])
        final_error_msg = f"All providers failed - {error_details}"
        logger.critical(f"LLM call failed for all providers: {final_error_msg}")
        return None, None, final_error_msg

    # Add the generate_content method
    async def generate_content(
        self, 
        prompt_params: Dict[str, Any],
        request_type: str,
        temperature: float = 0.7,
        max_tokens: int = 4096
    ) -> Tuple[Optional[str], Optional[str], Optional[str]]:
        """
        Generate content from LLM based on request type and parameters.
        
        Args:
            prompt_params: Dictionary of parameters for prompt construction
            request_type: Type of generation request (e.g., 'quick_draft', 'revise_message_draft')
            temperature: Temperature setting for generation
            max_tokens: Maximum tokens in response
            
        Returns:
            Tuple of (response_text, provider_name, error_message)
        """
        # Check for enhanced prompt from caller
        if prompt_params.get('use_enhanced_prompt') and prompt_params.get('enhanced_prompt'):
            logger.info(f"Using enhanced prompt for {request_type}")
            enhanced_prompt = prompt_params.get('enhanced_prompt')
            
            # For Anthropic - Use enhanced prompt as user message
            anthropic_messages = [
                {"role": "user", "content": enhanced_prompt}
            ]
            
            # For Gemini - Same enhanced prompt
            gemini_prompt_text = enhanced_prompt
            
            # Call LLM with enhanced prompt (no system prompt - everything in user message)
            return await self.execute_llm_call(
                anthropic_messages=anthropic_messages,
                gemini_prompt_text=gemini_prompt_text,
                temperature=temperature,
                max_tokens=max_tokens,
                gemini_response_mime_type="application/json"  # Request JSON response
            )
            
        # Handle other request types with default prompts
        # This is a simplified implementation - in production, you'd have specific prompt generators for each type
        if request_type == 'revise_message_draft':
            # Basic fallback implementation if no enhanced prompt is provided
            logger.warning("No enhanced prompt provided for revise_message_draft - using basic prompt")
            
            message_draft = prompt_params.get('message_draft', '')
            message_instructions = prompt_params.get('message_instructions', '')
            revision_instructions = prompt_params.get('revision_instructions', '')
            
            basic_prompt = f"""Please revise this message draft:
            
ORIGINAL INSTRUCTIONS: {message_instructions}

DRAFT TO REVISE:
{message_draft}

REVISION INSTRUCTIONS:
{revision_instructions}

Return your response as a JSON object with these fields:
{{
  "text_message": "The revised text message",
  "assistant_message": "A brief message to show the user",
  "task_title": "A short title for this task"
}}"""

            anthropic_messages = [
                {"role": "user", "content": basic_prompt}
            ]
            
            return await self.execute_llm_call(
                anthropic_messages=anthropic_messages,
                gemini_prompt_text=basic_prompt,
                temperature=temperature,
                max_tokens=max_tokens,
                gemini_response_mime_type="application/json"
            )
        
        # Add other request types as needed
        
        # Default case - return error for unhandled request type
        error_message = f"Unsupported request_type: {request_type}"
        logger.error(error_message)
        return None, None, error_message

    async def health_check(self) -> Dict[str, Any]:
        """Perform health check of AI generation service."""
        validation = self._validate_client_initialization()
        
        health_status = {
            'service_status': 'healthy' if (validation['anthropic_available'] or validation['gemini_available'] or validation['openai_available']) else 'unhealthy',
            'anthropic_status': 'available' if validation['anthropic_available'] else f"error: {validation['anthropic_error']}",
            'gemini_status': 'available' if validation['gemini_available'] else f"error: {validation['gemini_error']}",
            'openai_status': 'available' if validation['openai_available'] else f"error: {validation['openai_error']}",
            'timestamp': time.time()
        }
        
        return health_status

# --- Provider Function ---
# Singleton instance pattern might be useful if state needs to be managed,
# but for a stateless service like this, just returning a new instance is fine.
_ai_generation_service_instance = None

def get_ai_generation_service() -> AIGenerationService:
    """Gets a singleton instance of the AIGenerationService."""
    global _ai_generation_service_instance
    logger.debug("get_ai_generation_service() called")
    if _ai_generation_service_instance is None:
        logger.debug("Creating new AIGenerationService instance")
        _ai_generation_service_instance = AIGenerationService()
        logger.debug(f"AIGenerationService instance created: {_ai_generation_service_instance}")
    else:
        logger.debug("Using existing AIGenerationService instance")
    return _ai_generation_service_instance

# Remove trailing asyncio import if not needed elsewhere
# import asyncio

# --- Remove Prompt Generation Helpers ---
# def _generate_quick_draft_user_prompt_text(self, params: Dict[str, Any]) -> str: ... (Removed)
# def _generate_revise_draft_user_prompt_text(self, params: Dict[str, Any]) -> str: ... (Removed)

# --- Remove Deprecated Placeholders ---
# async def generate_task_from_instructions(...): ... (Removed)
# async def generate_draft_from_instructions(...): ... (Removed) 