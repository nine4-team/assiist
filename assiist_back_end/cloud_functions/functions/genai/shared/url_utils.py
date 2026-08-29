from urllib.parse import quote

def generate_sms_url(message, phone_number, platform):
    """Generate a platform-specific SMS URL.
    
    Args:
        message (str): The SMS message body.
        phone_number (str): The recipient's phone number.
        platform (str): The platform ('ios' or 'android').
        
    Returns:
        str: The SMS URL formatted for the specified platform.
    """
    # Clean the phone number - remove any non-digit characters
    cleaned_phone = ''.join(filter(str.isdigit, phone_number)) if phone_number else ''
    
    # URL encode the message using quote() instead of quote_plus() 
    # to avoid plus signs appearing in SMS text
    encoded_message = quote(message) if message else ''
    
    # Create platform-specific URL
    if platform.lower() == 'ios':
        # iOS format: sms:phone_number&body=message
        return f"sms:{cleaned_phone}&body={encoded_message}"
    else:
        # Android format: sms:phone_number?body=message
        return f"sms:{cleaned_phone}?body={encoded_message}"

def generate_group_sms_url(message, phone_numbers, platform):
    """Generate an SMS URL for group messaging based on platform.
    
    Args:
        message (str): The SMS message body.
        phone_numbers (list): List of recipient phone numbers.
        platform (str): The platform ('ios' or 'android').
        
    Returns:
        str: The SMS URL formatted for group messaging on the specified platform.
    """
    if not phone_numbers:
        return None
        
    # Clean phone numbers
    cleaned_phones = [''.join(filter(str.isdigit, phone)) for phone in phone_numbers if phone]
    
    # URL encode the message using quote() instead of quote_plus()
    # to avoid plus signs appearing in SMS text
    encoded_message = quote(message) if message else ''
    
    # Platform-specific group messaging format
    if platform.lower() == 'ios':
        # iOS allows comma-separated numbers: sms:number1,number2&body=message
        phone_list = ','.join(cleaned_phones)
        return f"sms:{phone_list}&body={encoded_message}"
    else:
        # Android uses semicolons: sms:number1;number2?body=message
        phone_list = ';'.join(cleaned_phones)
        return f"sms:{phone_list}?body={encoded_message}"

def insert_sms_url_in_reminder(reminder_template, message_to_encode, funnel_domain, contact_phone):
    """Insert an SMS URL into a reminder template by replacing [URL] placeholder.
    
    Args:
        reminder_template (str): The reminder text containing [URL] placeholder.
        message_to_encode (str): The message to encode in the SMS URL.
        funnel_domain (str): Legacy parameter - no longer used, kept for compatibility.
        contact_phone (str): The contact's phone number.
        
    Returns:
        str: The reminder with [URL] replaced by the SMS URL.
    """
    if not reminder_template or "[URL]" not in reminder_template:
        return reminder_template
    
    # Generate SMS URL using the existing utility
    sms_url = generate_sms_url(
        message=message_to_encode,
        phone_number=contact_phone,
        platform="ios"  # Default to iOS
    )
    
    # Replace [URL] placeholder with the generated SMS URL
    return reminder_template.replace("[URL]", sms_url)

def get_sms_data(message, recipients=None, platform=None):
    """Generate SMS data for the app.
    
    This function creates a simple data structure with the SMS URL and related information.
    
    Args:
        message (str): The SMS message body.
        recipients (str or list): Either a single phone number as string or a list of phone numbers.
        platform (str): The platform ('ios' or 'android').
        
    Returns:
        dict: A data structure with SMS URL and related information.
    """
    # Default to 'android' if no platform specified
    platform = platform or 'android'
    
    # Handle recipients parameter - convert single string to list if needed
    if recipients is None:
        recipient_list = []
    elif isinstance(recipients, str):
        recipient_list = [recipients] if recipients.strip() else []
    elif isinstance(recipients, list):
        recipient_list = [r for r in recipients if r and isinstance(r, str)]
    else:
        # Handle unexpected input
        recipient_list = []
    
    # Check if we have multiple recipients for a group message
    is_group = len(recipient_list) > 1
    
    # Generate appropriate URL
    if is_group:
        # It's a group message with multiple recipients
        sms_url = generate_group_sms_url(message, recipient_list, platform)
    else:
        # It's a single recipient message
        phone = recipient_list[0] if recipient_list else ""
        sms_url = generate_sms_url(message, phone, platform)
    
    # Create simple data structure
    return {
        "message": message,
        "recipients": recipient_list,
        "is_group": is_group,
        "platform": platform,
        "sms_url": sms_url
    }
