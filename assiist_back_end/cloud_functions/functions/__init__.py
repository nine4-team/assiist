# Export HTTP functions for discovery
try:
    from revise_draft import revise_message_draft
    __all__ = ['revise_message_draft']
except ImportError:
    print("Failed to import revise_message_draft in __init__.py")
    __all__ = []

try:
    from get_quick_draft import get_quick_draft
    if 'get_quick_draft' not in __all__:
        __all__.append('get_quick_draft')
except ImportError:
    print("Failed to import get_quick_draft in __init__.py")
