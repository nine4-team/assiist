"""
Simplified AIService implementation for deployment.
"""
from typing import Dict, Any, Optional

class AIService:
    """Simplified AIService implementation that can be used as a fallback."""
    
    def __init__(self):
        print("Initialized AIService stub")
    
    def generate(self, prompt: str, request_type: str, user_id: str, context: Dict[str, Any] = None) -> Optional[Dict[str, Any]]:
        """
        Generate content using AI.
        
        This stub implementation returns a simple task with placeholders.
        In production, it would actually call an LLM API.
        
        Args:
            prompt: The user's instructions
            request_type: Type of generation (e.g., 'quick_draft')
            user_id: ID of the requesting user
            context: Additional context data
            
        Returns:
            Dict with generated content or None if generation fails
        """
        print(f"AIService stub called with request_type: {request_type}, prompt: {prompt[:50]}...")
        
        # In a real implementation, this would call the LLM
        # For deployment, we just return a simple task
        contact_id = context.get('contact_id') if context else None
        
        return {
            'title': f"Generated {request_type} (stub)",
            'body': f"This is a stub implementation response for: {prompt[:100]}...",
            'type': 'message',
            'status': 'pending',
            'user_id': user_id,
            'contact_id': contact_id,
            'created_by': user_id
        } 