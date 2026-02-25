# -*- coding: utf-8 -*-
"""
Session Management Endpoints

Active endpoints:
  POST /api/v1/sessions/create
  POST /api/v1/sessions/{session_id}/message
  POST /api/v1/sessions/{session_id}/message/stream
  POST /api/v1/homework-followup/{session_id}/message

Redacted (backend never proxies these, moved to main.REDACTED.py):
  GET    /api/v1/sessions/{session_id}
  DELETE /api/v1/sessions/{session_id}
"""
import json as _json
import time as _time
from datetime import datetime
from typing import Dict, List, Optional, Any

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from src.services.improved_openai_service import EducationalAIService
from src.services.gemini_service import GeminiEducationalAIService
from src.services.prompt_service import AdvancedPromptService
from src.services.session_service import SessionService
from src.middleware.service_auth import optional_service_auth
from src.services.logger import setup_logger

logger = setup_logger(__name__)

router = APIRouter()

# Service singletons for this module
ai_service = EducationalAIService()
gemini_service = GeminiEducationalAIService()
prompt_service = AdvancedPromptService()
session_service = SessionService(ai_service, None)  # redis_client injected at startup via set_redis()


def set_redis(redis_client):
    """Called from main.py after Redis is initialised to inject the client."""
    global session_service
    session_service = SessionService(ai_service, redis_client)


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class SessionCreateRequest(BaseModel):
    student_id: str
    subject: str


class SessionResponse(BaseModel):
    session_id: str
    student_id: str
    subject: str
    created_at: str
    last_activity: str
    message_count: int


class SessionMessageRequest(BaseModel):
    message: str
    subject: Optional[str] = None
    image_data: Optional[str] = None
    system_prompt: Optional[str] = None
    question_context: Optional[Dict[str, Any]] = None
    deep_mode: Optional[bool] = False
    language: Optional[str] = "en"
    # Prior turns from the gateway DB — used to reseed in-memory session after
    # Live mode (or server restart) wiped the in-memory state.
    # Each item: {"role": "user"|"assistant", "content": str, "image_data": str|None}
    prior_turns: Optional[List[Dict[str, Any]]] = None


class SessionMessageResponse(BaseModel):
    session_id: str
    ai_response: str
    tokens_used: int
    compressed: bool
    follow_up_suggestions: Optional[List[Dict[str, str]]] = None


class HomeworkFollowupRequest(BaseModel):
    message: str
    question_context: Dict[str, Any]


class HomeworkFollowupResponse(BaseModel):
    session_id: str
    ai_response: str
    tokens_used: int
    compressed: bool


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def select_chat_model(message: str, subject: str, conversation_length: int = 0):
    """Select optimal model based on query complexity. Returns (model_name, max_tokens)."""
    msg = message.lower().strip()
    msg_length = len(msg)

    if msg_length < 30:
        return ("gpt-3.5-turbo", 500)

    greeting_patterns = [
        'hi', 'hello', 'hey', 'thanks', 'thank you', 'ok', 'okay',
        'got it', 'i see', 'understood', 'yes', 'no', 'maybe'
    ]
    if msg in greeting_patterns or msg.startswith(tuple(greeting_patterns)):
        return ("gpt-3.5-turbo", 500)

    complex_keywords = [
        'prove', 'derive', 'calculate', 'solve', 'compute', 'evaluate',
        'analyze', 'compare', 'contrast', 'demonstrate', 'justify',
        'step by step', 'detailed', 'in depth', 'thoroughly',
        'why', 'how does', 'what causes', 'explain why',
        'theorem', 'formula', 'equation', 'proof', 'method'
    ]
    if any(keyword in msg for keyword in complex_keywords):
        return ("gpt-4o-mini", 1500)

    medium_keywords = [
        'explain', 'describe', 'what is', 'how to', 'can you help',
        'show me', 'tell me about', 'what are', 'give example'
    ]
    if any(keyword in msg for keyword in medium_keywords):
        return ("gpt-4o-mini", 1200)

    stem_subjects = ['mathematics', 'physics', 'chemistry', 'biology', 'computer science']
    if subject and subject.lower() in stem_subjects:
        return ("gpt-4o-mini", 1500)

    if msg_length > 150:
        return ("gpt-4o-mini", 1500)

    return ("gpt-3.5-turbo", 800)


async def generate_follow_up_suggestions(ai_response: str, user_message: str, subject: str):
    """Generate 3 contextual follow-up suggestions. Returns list of {key, value} dicts."""
    try:
        def detect_chinese(text: str) -> bool:
            return any(0x4E00 <= ord(char) <= 0x9FFF for char in text)

        is_chinese = detect_chinese(ai_response)

        if is_chinese:
            language_instruction = (
                "CRITICAL: The AI response is in CHINESE. Generate all suggestions in CHINESE (简体中文). "
                "All 'key' labels must be 2-4 Chinese characters. All 'value' questions must be in Chinese."
            )
        else:
            language_instruction = (
                "LANGUAGE: The AI response is in ENGLISH. Generate all suggestions in ENGLISH. "
                "All 'key' labels must be 2-4 words. All 'value' questions must be in English."
            )

        suggestion_prompt = f"""Based on this educational conversation, generate 3 contextual follow-up questions.

Student asked: {user_message[:200]}
AI explained: {ai_response[:500]}
Subject: {subject}

{language_instruction}

Format as JSON array:
[
  {{"key": "Short button label (2-4 words)", "value": "Full question to ask"}},
  {{"key": "Short button label", "value": "Full question to ask"}},
  {{"key": "Short button label", "value": "Full question to ask"}}
]

Return ONLY the JSON array, no other text."""

        import re as _re
        response = await ai_service.client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": suggestion_prompt}],
            temperature=0.7,
            max_tokens=300
        )
        suggestion_text = response.choices[0].message.content.strip()
        json_match = _re.search(r'\[.*\]', suggestion_text, _re.DOTALL)
        if json_match:
            suggestions = _json.loads(json_match.group())
            valid = [s for s in suggestions if isinstance(s, dict) and 'key' in s and 'value' in s]
            return valid[:3]
        return []
    except Exception:
        return []


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


async def _seed_session_from_prior_turns(session, session_id: str, prior_turns: List[Dict[str, Any]]):
    """
    Pre-populate a freshly-created in-memory session with prior turns fetched
    from the gateway DB.  Called when is_new_session=True AND prior_turns is
    provided (i.e. the AI Engine lost state after a Live mode session or restart).

    Each item in prior_turns: {"role": "user"|"assistant", "content": str, "image_data": str|None}
    """
    seeded = 0
    for turn in prior_turns:
        role = turn.get("role", "")
        content = turn.get("content", "").strip()
        image_data = turn.get("image_data")  # base64 string or None
        if role not in ("user", "assistant") or not content:
            continue
        session.add_message(role, content, image_data=image_data if role == "user" else None)
        seeded += 1
    import logging as _log
    _log.getLogger("sessions").info(
        f"[Session] seeded {seeded}/{len(prior_turns)} prior turns into in-memory session={session_id[:8]}"
    )

@router.post("/api/v1/sessions/create", response_model=SessionResponse)
async def create_session(request: SessionCreateRequest):
    """Create a new study session. Sessions maintain conversation history and context."""
    try:
        session = await session_service.create_session(
            student_id=request.student_id,
            subject=request.subject
        )
        return SessionResponse(
            session_id=session.session_id,
            student_id=session.student_id,
            subject=session.subject,
            created_at=session.created_at.isoformat(),
            last_activity=session.last_activity.isoformat(),
            message_count=len(session.messages)
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Session creation error: {str(e)}")


@router.post("/api/v1/sessions/{session_id}/message", response_model=SessionMessageResponse)
async def send_session_message(session_id: str, request: SessionMessageRequest):
    """
    Send a message in an existing session (non-streaming).
    Accepts system_prompt for prompt caching (40-50% token reduction).
    """
    try:
        session = await session_service.get_session(session_id)
        is_new_session = session is None
        if not session:
            session = await session_service.create_session(
                student_id="auto_created",
                subject=request.subject or "general"
            )
            session.session_id = session_id
            session_service.sessions[session_id] = session

        # Reseed in-memory session from gateway DB turns when state was lost
        # (e.g. after Live mode or server restart).
        if is_new_session and request.prior_turns:
            await _seed_session_from_prior_turns(session, session_id, request.prior_turns)

        await session_service.add_message_to_session(
            session_id=session_id,
            role="user",
            content=request.message,
            image_data=request.image_data,
        )

        if request.system_prompt:
            system_prompt = request.system_prompt
        else:
            system_prompt = prompt_service.create_enhanced_prompt(
                question=request.message,
                subject_string=request.subject or session.subject,
                context={"student_id": session.student_id, "language": request.language}
            )

        context_messages = session.get_context_for_api(system_prompt)

        session_has_images = any(msg.has_image() for msg in session.messages)
        if request.deep_mode:
            selected_model = "o4-mini"
            max_tokens = 4000
        elif session_has_images:
            selected_model = "gpt-4o-mini"
            max_tokens = 4096
        else:
            selected_model, max_tokens = select_chat_model(
                message=request.message,
                subject=session.subject,
                conversation_length=len(session.messages)
            )

        openai_params = {
            "model": selected_model,
            "messages": context_messages,
            "stream": False
        }
        if selected_model.startswith('o4') or selected_model.startswith('o1'):
            openai_params["max_completion_tokens"] = max_tokens
            openai_params["temperature"] = 1
        else:
            openai_params["max_tokens"] = max_tokens
            openai_params["temperature"] = 0.3

        response = await ai_service.client.chat.completions.create(**openai_params)
        ai_response = response.choices[0].message.content
        tokens_used = response.usage.total_tokens

        suggestions = await generate_follow_up_suggestions(
            ai_response=ai_response,
            user_message=request.message,
            subject=request.subject or session.subject
        )

        updated_session = await session_service.add_message_to_session(
            session_id=session_id,
            role="assistant",
            content=ai_response
        )

        return SessionMessageResponse(
            session_id=session_id,
            ai_response=ai_response,
            tokens_used=tokens_used,
            compressed=updated_session.compressed_context is not None,
            follow_up_suggestions=suggestions if suggestions else None
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Session message error: {str(e)}")


@router.post("/api/v1/sessions/{session_id}/message/stream")
async def send_session_message_stream(session_id: str, request: SessionMessageRequest):
    """
    Send a message in an existing session with SSE streaming response.
    Intelligent model routing: 50-70% cost reduction on simple queries.
    """
    try:
        session = await session_service.get_session(session_id)
        is_new_session = session is None

        if not session:
            session = await session_service.create_session(
                student_id="auto_created",
                subject=request.subject or "general"
            )
            session.session_id = session_id
            session_service.sessions[session_id] = session

        # ── CONTEXT FLOW LOG ─────────────────────────────────────────────────
        # Shows what the AI Engine's in-memory session contains before processing.
        # If Live mode turns are missing here, they were stored in the gateway DB
        # (conversations table) but never injected into this in-memory session.
        in_memory_count = len(session.messages) if session else 0
        in_memory_preview = [
            {"role": m.role, "preview": (str(m.content) if hasattr(m, "content") else "")[:60].replace("\n", " ")}
            for m in (session.messages[-4:] if session and session.messages else [])
        ]
        import logging as _logging
        _logging.getLogger("sessions").info(
            f"[Session][stream] msg received | session={session_id[:8]} | "
            f"new_in_memory={is_new_session} | in_memory_msgs={in_memory_count} | "
            f"prior_turns_received={len(request.prior_turns) if request.prior_turns else 0} | "
            f"last_4={in_memory_preview} | "
            f"user_msg={request.message[:80].replace(chr(10), ' ')!r}"
        )

        # Reseed in-memory session from gateway DB turns when state was lost
        # (e.g. after Live mode or server restart).
        if is_new_session and request.prior_turns:
            await _seed_session_from_prior_turns(session, session_id, request.prior_turns)

        await session_service.add_message_to_session(
            session_id=session_id,
            role="user",
            content=request.message,
            image_data=request.image_data,
        )

        is_homework_followup = request.question_context is not None

        if request.system_prompt:
            system_prompt = request.system_prompt
        elif is_homework_followup:
            system_prompt = prompt_service.create_homework_followup_prompt(
                question_context=request.question_context,
                student_message=request.message,
                session_id=session_id
            )
        else:
            system_prompt = prompt_service.create_enhanced_prompt(
                question=request.message,
                subject_string=request.subject or session.subject,
                context={"student_id": session.student_id, "language": request.language}
            )

        context_messages = session.get_context_for_api(system_prompt)

        session_has_images = any(msg.has_image() for msg in session.messages)
        if request.deep_mode:
            selected_model = "o4-mini"
            max_tokens = 4000
        elif session_has_images:
            selected_model = "gpt-4o-mini"
            max_tokens = 4096
        else:
            selected_model, max_tokens = select_chat_model(
                message=request.message,
                subject=session.subject,
                conversation_length=len(session.messages)
            )

        async def stream_generator():
            accumulated_content = ""
            try:
                start_event = {
                    'type': 'start',
                    'timestamp': datetime.now().isoformat(),
                    'session_id': session_id,
                    'model': selected_model
                }
                yield f"data: {_json.dumps(start_event)}\n\n"

                openai_params = {
                    "model": selected_model,
                    "messages": context_messages,
                    "stream": True
                }
                if selected_model.startswith('o4') or selected_model.startswith('o1'):
                    openai_params["max_completion_tokens"] = max_tokens
                    openai_params["temperature"] = 1
                else:
                    openai_params["max_tokens"] = max_tokens
                    openai_params["temperature"] = 0.3

                stream = await ai_service.client.chat.completions.create(**openai_params)

                async for chunk in stream:
                    if chunk.choices and len(chunk.choices) > 0:
                        delta = chunk.choices[0].delta
                        if delta.content:
                            accumulated_content += delta.content
                            yield f"data: {_json.dumps({'type': 'content', 'content': accumulated_content, 'delta': delta.content})}\n\n"

                        if chunk.choices[0].finish_reason:
                            await session_service.add_message_to_session(
                                session_id=session_id,
                                role="assistant",
                                content=accumulated_content
                            )

                            yield f"data: {_json.dumps({'type': 'end', 'finish_reason': chunk.choices[0].finish_reason, 'content': accumulated_content, 'session_id': session_id})}\n\n"

                            suggestions = await generate_follow_up_suggestions(
                                ai_response=accumulated_content,
                                user_message=request.message,
                                subject=session.subject
                            )

                            if suggestions:
                                try:
                                    serializable = [
                                        {'key': str(s.get('key', '')), 'value': str(s.get('value', ''))}
                                        for s in suggestions if isinstance(s, dict)
                                    ]
                                    if serializable:
                                        yield f"data: {_json.dumps({'type': 'suggestions', 'suggestions': serializable, 'session_id': session_id})}\n\n"
                                except Exception:
                                    pass

                            break

            except Exception as e:
                import traceback
                error_msg = f"Streaming error: {str(e) or 'Unknown error'}"
                yield f"data: {_json.dumps({'type': 'error', 'error': error_msg, 'traceback': traceback.format_exc()[:500]})}\n\n"

        return StreamingResponse(
            stream_generator(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "Connection": "keep-alive", "X-Accel-Buffering": "no"}
        )

    except Exception as e:
        import traceback
        error_msg = f"Session streaming error: {str(e) or 'Unknown error'}"

        async def error_generator():
            yield f"data: {_json.dumps({'type': 'error', 'error': error_msg, 'traceback': traceback.format_exc()[:500]})}\n\n"

        return StreamingResponse(error_generator(), media_type="text/event-stream")


@router.post("/api/v1/homework-followup/{session_id}/message", response_model=HomeworkFollowupResponse)
async def process_homework_followup(
    session_id: str,
    request: HomeworkFollowupRequest,
    service_info=optional_service_auth()
):
    """
    Process homework follow-up questions with AI grade self-validation.
    Includes full homework context and detects/returns structured grade corrections.
    """
    start_time = _time.time()
    try:
        session = await session_service.get_session(session_id)
        if not session:
            subject = request.question_context.get('subject', 'general')
            session = await session_service.create_session(
                student_id=request.question_context.get('student_id', 'anonymous'),
                subject=subject
            )

        await session_service.add_message_to_session(
            session_id=session.session_id,
            role="user",
            content=request.message
        )

        system_prompt = prompt_service.create_homework_followup_prompt(
            question_context=request.question_context,
            student_message=request.message,
            session_id=session.session_id
        )

        context_messages = session.get_context_for_api(system_prompt)

        response = await ai_service.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=context_messages,
            temperature=0.3,
            max_tokens=2000,
            stream=False
        )

        ai_response = response.choices[0].message.content
        tokens_used = response.usage.total_tokens

        updated_session = await session_service.add_message_to_session(
            session_id=session.session_id,
            role="assistant",
            content=ai_response
        )

        return HomeworkFollowupResponse(
            session_id=session.session_id,
            ai_response=ai_response,
            tokens_used=tokens_used,
            compressed=updated_session.compressed_context is not None
        )

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        logger.debug(f"❌ Homework Follow-up Error: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Homework follow-up processing error: {str(e)}")
