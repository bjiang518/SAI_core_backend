"""
Prompt Localization Data for StudyAI AI Engine

All language-specific prompt instructions live here.
To add a new language: add a new key to each dict below.
Logic files (prompt_service.py, improved_openai_service.py) never need to change.

Supported language codes (mirrors iOS LanguageSettingsView):
  "en"      - English (default)
  "zh-Hans" - Simplified Chinese
  "zh-Hant" - Traditional Chinese

Backend question-generation-v2.js sends "zh-CN" / "zh-TW" — these are
normalized to "zh-Hans" / "zh-Hant" at the AI Engine boundary (see normalize_language()).
"""

from typing import Optional


# ---------------------------------------------------------------------------
# Language normalization
# Accepts both BCP-47 variants the backend may send and returns a canonical key.
# ---------------------------------------------------------------------------

_LANG_ALIASES = {
    "zh-cn": "zh-Hans",
    "zh-hans": "zh-Hans",
    "zh-tw": "zh-Hant",
    "zh-hant": "zh-Hant",
    "en": "en",
}

def normalize_language(language: Optional[str], fallback: str = "en") -> str:
    """Normalize any incoming language code to a canonical key used in this file."""
    if not language:
        return fallback
    return _LANG_ALIASES.get(language.lower(), fallback)


# ---------------------------------------------------------------------------
# Random question generation — language instruction appended to prompt
#
# Each value is a plain string injected at the end of the prompt.
# Keep instructions short and unambiguous so the model follows them reliably.
# ---------------------------------------------------------------------------

RANDOM_QUESTIONS_LANG_INSTRUCTION = {
    "en": (
        "Write all question text, answer options, explanations, and topic fields in English."
    ),
    "zh-Hans": (
        "请将所有题目、选项、解析和topic字段全部用简体中文书写。"
        "数学公式仍使用LaTeX符号，其余所有文字内容必须是简体中文。"
    ),
    "zh-Hant": (
        "請將所有題目、選項、解析和topic欄位全部用繁體中文書寫。"
        "數學公式仍使用LaTeX符號，其餘所有文字內容必須是繁體中文。"
    ),
}

# User-turn trigger message (the short "Generate now" line sent as the user role)
RANDOM_QUESTIONS_USER_MESSAGE = {
    "en":      "Generate {count} random questions for {subject} now.",
    "zh-Hans": "请立即为{subject}生成{count}道练习题。",
    "zh-Hant": "請立即為{subject}生成{count}道練習題。",
}

# ---------------------------------------------------------------------------
# Archive-based question generation — language instruction + user message
# ---------------------------------------------------------------------------

ARCHIVE_QUESTIONS_LANG_INSTRUCTION = {
    "en": (
        "Write all question text, answer options, explanations, and topic fields in English."
    ),
    "zh-Hans": (
        "请将所有题目、选项、解析和topic字段全部用简体中文书写。"
        "数学公式仍使用LaTeX符号，其余所有文字内容必须是简体中文。"
    ),
    "zh-Hant": (
        "請將所有題目、選項、解析和topic欄位全部用繁體中文書寫。"
        "數學公式仍使用LaTeX符號，其餘所有文字內容必須是繁體中文。"
    ),
}

ARCHIVE_QUESTIONS_USER_MESSAGE = {
    "en":      "Generate {count} personalized questions based on the conversation history for {subject}.",
    "zh-Hans": "请根据对话历史为{subject}生成{count}道个性化练习题。",
    "zh-Hant": "請根據對話歷史為{subject}生成{count}道個性化練習題。",
}

# ---------------------------------------------------------------------------
# Mistake-based question generation — language instruction + user message
# ---------------------------------------------------------------------------

MISTAKE_QUESTIONS_LANG_INSTRUCTION = {
    "en": (
        "Write all question text, answer options, explanations, and topic fields in English."
    ),
    "zh-Hans": (
        "请将所有题目、选项、解析和topic字段全部用简体中文书写。"
        "数学公式仍使用LaTeX符号，其余所有文字内容必须是简体中文。"
    ),
    "zh-Hant": (
        "請將所有題目、選項、解析和topic欄位全部用繁體中文書寫。"
        "數學公式仍使用LaTeX符號，其餘所有文字內容必須是繁體中文。"
    ),
}

MISTAKE_QUESTIONS_USER_MESSAGE = {
    "en":      "Generate {count} remedial questions based on the mistake patterns for {subject}.",
    "zh-Hans": "请根据错题模式为{subject}生成{count}道补救练习题。",
    "zh-Hant": "請根據錯題模式為{subject}生成{count}道補救練習題。",
}

# ---------------------------------------------------------------------------
# Homework grading — language instruction appended to _create_json_schema_prompt
#
# Injected at the very end of the prompt, after all rules.
# Keep it short — the model must still follow strict JSON schema rules.
# ---------------------------------------------------------------------------

HOMEWORK_LANG_INSTRUCTION = {
    "en": "",  # No extra instruction needed for English
    "zh-Hans": (
        "\n\nLANGUAGE: Write all 'feedback', 'summary_text', and 'overall_feedback' text fields "
        "in Simplified Chinese (简体中文). All other fields (grade, question_type, subject, etc.) "
        "keep as English keywords exactly as specified above."
    ),
    "zh-Hant": (
        "\n\nLANGUAGE: Write all 'feedback', 'summary_text', and 'overall_feedback' text fields "
        "in Traditional Chinese (繁體中文). All other fields (grade, question_type, subject, etc.) "
        "keep as English keywords exactly as specified above."
    ),
}

# ---------------------------------------------------------------------------
# Single-question grading feedback — appended at end of grading prompt
#
# Only the 'feedback' field is localized; structural keywords (score,
# is_correct, confidence, correct_answer) must stay in English for iOS parser.
# ---------------------------------------------------------------------------

GRADING_FEEDBACK_LANG_INSTRUCTION = {
    "en": "",  # No extra instruction needed for English
    "zh-Hans": (
        "\n\nLANGUAGE: Write the 'feedback' field value in Simplified Chinese (简体中文). "
        "Keep all other JSON field names and non-text values (score, is_correct, confidence, correct_answer) in English."
    ),
    "zh-Hant": (
        "\n\nLANGUAGE: Write the 'feedback' field value in Traditional Chinese (繁體中文). "
        "Keep all other JSON field names and non-text values (score, is_correct, confidence, correct_answer) in English."
    ),
}
