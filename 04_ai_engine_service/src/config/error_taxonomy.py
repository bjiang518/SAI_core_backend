"""
Fixed error type taxonomy - 9 universal categories
"""

ERROR_TYPES = {
    "conceptual_misunderstanding": {
        "description": "Student has wrong mental model or doesn't understand core concept",
        "examples": ["Thinks area = perimeter", "Confuses mitosis with meiosis"]
    },
    "procedural_error": {
        "description": "Wrong method, formula, or steps applied",
        "examples": ["Used wrong formula", "Applied steps in wrong order"]
    },
    "calculation_mistake": {
        "description": "Arithmetic or computational error",
        "examples": ["5 + 3 = 9", "Forgot to carry the 1"]
    },
    "reading_comprehension": {
        "description": "Missed critical question requirement or constraint",
        "examples": ["Problem asks 'at least' but solved for 'exactly'"]
    },
    "notation_error": {
        "description": "Wrong symbols, units, or notation",
        "examples": ["Forgot units", "Used wrong variable names"]
    },
    "incomplete_work": {
        "description": "Partial solution or missing steps",
        "examples": ["Showed setup but no final answer"]
    },
    "careless_mistake": {
        "description": "Student knows concept but made typo/slip",
        "examples": ["Wrote 'x = 5' when they meant 'x = -5'"]
    },
    "time_constraint": {
        "description": "Rushed or incomplete due to time pressure",
        "examples": ["Multiple skipped questions"]
    },
    "no_attempt": {
        "description": "Question left blank or minimal effort",
        "examples": ["Empty response", "Just wrote '?'"]
    }
}

def get_error_type_list():
    return list(ERROR_TYPES.keys())

def validate_error_type(error_type):
    return error_type in ERROR_TYPES or error_type is None

def get_error_type_prompt():
    types_text = "\n".join([
        f"- **{key}**: {value['description']}"
        for key, value in ERROR_TYPES.items()
    ])
    return f"Choose EXACTLY ONE error type:\n\n{types_text}"
