import re
import json
import logging

logger = logging.getLogger(__name__)

def extract_json(text: str, debug: bool = False) -> dict:
    """Extracts the first valid JSON object from a string.

    Handles JSON within markdown code blocks (```json ... ```) or raw JSON.
    Cleans trailing commas before parsing.

    Args:
        text (str): The input string potentially containing JSON.
        debug (bool): If True, print debug messages on failure.

    Returns:
        dict: A dictionary containing {"extracted_json": str|None, "extra_text": str}
              where extracted_json is the stringified JSON object found, and
              extra_text is the remaining text. Returns None for extracted_json
              if no valid JSON is found.
    """
    if not isinstance(text, str):
        logger.warning("extract_json called with non-string input.")
        return {"extracted_json": None, "extra_text": text or ""}

    # Regex patterns
    # Pattern to find JSON within ```json ... ``` block (captures content inside {})
    code_block_pattern = re.compile(r'```(?:json)?\s*({.*?})\s*```', re.DOTALL)
    # Pattern to find JSON within generic ``` ... ``` block (captures content inside {})
    generic_code_block_pattern = re.compile(r'```.*?({.*?})\s*```', re.DOTALL)
    # Pattern to find JSON that might start immediately after ```, looking for balanced {}
    starts_with_code_block_pattern = re.compile(r'^```(?:json)?\s*({.*)', re.DOTALL)

    patterns_to_try = [
        code_block_pattern,
        generic_code_block_pattern,
        # starts_with_code_block_pattern # This one is handled differently below
    ]

    # 1. & 2. Check standard code block patterns first
    for i, pattern in enumerate(patterns_to_try):
        match = pattern.search(text)
        if match:
            json_candidate = match.group(1)
            try:
                # Clean trailing commas
                cleaned_json = re.sub(r',(\s*[}\]])', r'\1', json_candidate)
                parsed = json.loads(cleaned_json)
                if isinstance(parsed, dict):
                    extracted_json_str = json.dumps(parsed) # Re-stringify for consistency
                    extra_text = text.replace(match.group(0), "", 1).strip()
                    if debug: logger.debug(f"JSON extracted using pattern {i+1}.")
                    return {"extracted_json": extracted_json_str, "extra_text": extra_text}
            except json.JSONDecodeError as e:
                if debug: logger.debug(f"JSON parsing failed for pattern {i+1}: {e}")
                # Continue to next pattern or fallback

    # 3. Check if text starts with ```json and contains JSON (handles missing closing ```)
    match = starts_with_code_block_pattern.match(text)
    if match:
        partial_content = match.group(1)
        brace_level = 0
        end_index = -1
        # Find balanced closing brace
        for i, char in enumerate(partial_content):
            if char == '{':
                brace_level += 1
            elif char == '}':
                brace_level -= 1
                if brace_level == 0:
                    end_index = i
                    break
        if end_index != -1:
            json_candidate = partial_content[:end_index + 1]
            try:
                cleaned_json = re.sub(r',(\s*[}\]])', r'\1', json_candidate)
                parsed = json.loads(cleaned_json)
                if isinstance(parsed, dict):
                    extracted_json_str = json.dumps(parsed)
                    # Determine extra text: everything after the found JSON object
                    original_end_index_in_text = text.find(json_candidate) + len(json_candidate)
                    extra_text = text[original_end_index_in_text:].strip()
                    if debug: logger.debug("JSON extracted using starts_with_code_block pattern.")
                    return {"extracted_json": extracted_json_str, "extra_text": extra_text}
            except json.JSONDecodeError as e:
                if debug: logger.debug(f"JSON parsing from partial code block failed: {e}")
                # Fall through to final fallback

    # 4. Fallback: Find the first occurrence of '{' and try to parse until matching '}'
    try:
        start_index = text.find('{')
        if start_index != -1:
            brace_level = 0
            end_index = -1
            for i in range(start_index, len(text)):
                char = text[i]
                if char == '{':
                    brace_level += 1
                elif char == '}':
                    brace_level -= 1
                    if brace_level == 0:
                        end_index = i
                        break # Found the end of the first top-level JSON object

            if end_index != -1:
                json_candidate = text[start_index : end_index + 1]
                try:
                    cleaned_json = re.sub(r',(\s*[}\]])', r'\1', json_candidate)
                    parsed = json.loads(cleaned_json)
                    if isinstance(parsed, dict):
                        extracted_json_str = json.dumps(parsed)
                        extra_text = (text[:start_index] + text[end_index+1:]).strip()
                        if debug: logger.debug("JSON extracted using direct brace matching fallback.")
                        return {"extracted_json": extracted_json_str, "extra_text": extra_text}
                except json.JSONDecodeError as e:
                     if debug: logger.debug(f"Direct JSON parsing fallback failed: {e}")
                     # Fall through
    except Exception as e:
        # Catch potential errors during string manipulation in fallback
        if debug: logger.debug(f"Error during fallback JSON extraction: {e}")

    # If no JSON found after all attempts
    if debug: logger.debug("No valid JSON object found in the text.")
    return {"extracted_json": None, "extra_text": text} 