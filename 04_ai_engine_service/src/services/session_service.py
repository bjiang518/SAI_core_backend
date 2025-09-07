"""
Session Management Service with Intelligent Context Compression
Handles conversation memory, token limits, and context summarization
"""

import json
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any

# Try to import tiktoken for token counting
try:
    import tiktoken
    TIKTOKEN_AVAILABLE = True
except ImportError:
    TIKTOKEN_AVAILABLE = False
    print("⚠️ tiktoken not available, using approximate token counting")

class SessionMessage:
    def __init__(self, role: str, content: str, timestamp: datetime = None, tokens: int = 0):
        self.role = role
        self.content = content
        self.timestamp = timestamp or datetime.now()
        self.tokens = tokens
    
    def to_dict(self):
        return {
            "role": self.role,
            "content": self.content,
            "timestamp": self.timestamp.isoformat(),
            "tokens": self.tokens
        }
    
    @classmethod
    def from_dict(cls, data: dict):
        return cls(
            role=data["role"],
            content=data["content"],
            timestamp=datetime.fromisoformat(data["timestamp"]),
            tokens=data.get("tokens", 0)
        )

class StudySession:
    def __init__(self, session_id: str, student_id: str, subject: str):
        self.session_id = session_id
        self.student_id = student_id
        self.subject = subject
        self.messages: List[SessionMessage] = []
        self.created_at = datetime.now()
        self.last_activity = datetime.now()
        self.compressed_context: Optional[str] = None
        self.total_tokens = 0
        
        # Token limits for different models
        self.max_context_tokens = 4000  # Conservative limit for gpt-4o-mini
        self.compression_threshold = 3000  # Start compressing at 3k tokens
        self.keep_recent_messages = 6  # Always keep last 6 messages uncompressed
    
    def add_message(self, role: str, content: str) -> SessionMessage:
        """Add a new message to the session."""
        # Count tokens in the message
        if TIKTOKEN_AVAILABLE:
            try:
                encoding = tiktoken.encoding_for_model("gpt-4o-mini")
                tokens = len(encoding.encode(content))
            except Exception:
                # Fallback to approximate counting
                tokens = len(content.split()) * 1.3  # Approximate: ~1.3 tokens per word
        else:
            # Approximate token counting: ~1.3 tokens per word
            tokens = int(len(content.split()) * 1.3)
        
        message = SessionMessage(role, content, tokens=int(tokens))
        self.messages.append(message)
        self.total_tokens += int(tokens)
        self.last_activity = datetime.now()
        
        return message
    
    def get_context_for_api(self, system_prompt: str) -> List[Dict[str, str]]:
        """Get properly formatted context for OpenAI API with compression if needed."""
        
        # System prompt
        context = [{"role": "system", "content": system_prompt}]
        
        # Check if compression is needed
        if self.total_tokens > self.compression_threshold:
            # Add compressed context if available
            if self.compressed_context:
                context.append({
                    "role": "system", 
                    "content": f"Previous conversation summary: {self.compressed_context}"
                })
            
            # Add only recent messages
            recent_messages = self.messages[-self.keep_recent_messages:]
            for msg in recent_messages:
                context.append({"role": msg.role, "content": msg.content})
        else:
            # Add all messages if under threshold
            for msg in self.messages:
                context.append({"role": msg.role, "content": msg.content})
        
        return context
    
    def to_dict(self):
        return {
            "session_id": self.session_id,
            "student_id": self.student_id,
            "subject": self.subject,
            "messages": [msg.to_dict() for msg in self.messages],
            "created_at": self.created_at.isoformat(),
            "last_activity": self.last_activity.isoformat(),
            "compressed_context": self.compressed_context,
            "total_tokens": self.total_tokens
        }
    
    @classmethod
    def from_dict(cls, data: dict):
        session = cls(
            session_id=data["session_id"],
            student_id=data["student_id"],
            subject=data["subject"]
        )
        session.created_at = datetime.fromisoformat(data["created_at"])
        session.last_activity = datetime.fromisoformat(data["last_activity"])
        session.compressed_context = data.get("compressed_context")
        session.total_tokens = data.get("total_tokens", 0)
        session.messages = [SessionMessage.from_dict(msg) for msg in data["messages"]]
        return session

class SessionService:
    """
    Manages study sessions with intelligent context compression.
    Uses Redis for production or in-memory for development.
    """
    
    def __init__(self, ai_service, redis_client=None):
        self.ai_service = ai_service
        self.redis_client = redis_client
        self.sessions: Dict[str, StudySession] = {}  # Fallback in-memory storage
        self.session_ttl = timedelta(hours=24)  # Sessions expire after 24 hours
    
    async def create_session(self, student_id: str, subject: str) -> StudySession:
        """Create a new study session."""
        session_id = str(uuid.uuid4())
        session = StudySession(session_id, student_id, subject)
        
        await self._store_session(session)
        return session
    
    async def get_session(self, session_id: str) -> Optional[StudySession]:
        """Retrieve a session by ID."""
        if self.redis_client:
            # Try Redis first
            try:
                session_data = await self.redis_client.get(f"session:{session_id}")
                if session_data:
                    return StudySession.from_dict(json.loads(session_data))
            except Exception as e:
                print(f"Redis error: {e}")
        
        # Fallback to in-memory
        return self.sessions.get(session_id)
    
    async def _store_session(self, session: StudySession):
        """Store session in Redis or memory."""
        if self.redis_client:
            try:
                await self.redis_client.setex(
                    f"session:{session.session_id}",
                    int(self.session_ttl.total_seconds()),
                    json.dumps(session.to_dict())
                )
                return
            except Exception as e:
                print(f"Redis error: {e}")
        
        # Fallback to in-memory
        self.sessions[session.session_id] = session
    
    async def compress_session_context(self, session: StudySession) -> str:
        """Use AI to compress older conversation context."""
        
        # Get messages to compress (all except recent ones)
        messages_to_compress = session.messages[:-session.keep_recent_messages]
        
        if not messages_to_compress:
            return ""
        
        # Create conversation text for compression
        conversation_text = "\n".join([
            f"{msg.role.title()}: {msg.content}" 
            for msg in messages_to_compress
        ])
        
        compression_prompt = f"""Please create a concise summary of this educational conversation between a student and AI tutor in {session.subject}. 

Focus on:
1. Key concepts discussed
2. Problems solved
3. Student's understanding progress
4. Important context for future questions

Keep the summary under 200 words but preserve all important educational context.

Conversation to summarize:
{conversation_text}

Summary:"""
        
        try:
            response = await self.ai_service.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[{"role": "user", "content": compression_prompt}],
                temperature=0.1,
                max_tokens=300
            )
            
            compressed = response.choices[0].message.content
            session.compressed_context = compressed
            
            # Remove compressed messages to save tokens
            session.messages = session.messages[-session.keep_recent_messages:]
            
            # Recalculate token count
            if TIKTOKEN_AVAILABLE:
                try:
                    encoding = tiktoken.encoding_for_model("gpt-4o-mini")
                    session.total_tokens = sum(
                        len(encoding.encode(msg.content)) for msg in session.messages
                    )
                except Exception:
                    # Fallback to approximate counting
                    session.total_tokens = sum(
                        int(len(msg.content.split()) * 1.3) for msg in session.messages
                    )
            else:
                # Approximate token counting
                session.total_tokens = sum(
                    int(len(msg.content.split()) * 1.3) for msg in session.messages
                )
            
            await self._store_session(session)
            return compressed
            
        except Exception as e:
            print(f"Compression error: {e}")
            return "Previous conversation context available."
    
    async def add_message_to_session(
        self, 
        session_id: str, 
        role: str, 
        content: str
    ) -> Optional[StudySession]:
        """Add a message to an existing session with auto-compression."""
        
        session = await self.get_session(session_id)
        if not session:
            return None
        
        # Add the message
        session.add_message(role, content)
        
        # Check if compression is needed
        if session.total_tokens > session.compression_threshold and not session.compressed_context:
            print(f"🗜️ Compressing session {session_id} context ({session.total_tokens} tokens)")
            await self.compress_session_context(session)
        
        await self._store_session(session)
        return session
    
    async def cleanup_expired_sessions(self):
        """Clean up expired sessions (for in-memory storage)."""
        if self.redis_client:
            return  # Redis handles TTL automatically
        
        cutoff = datetime.now() - self.session_ttl
        expired_sessions = [
            sid for sid, session in self.sessions.items()
            if session.last_activity < cutoff
        ]
        
        for sid in expired_sessions:
            del self.sessions[sid]
        
        print(f"🧹 Cleaned up {len(expired_sessions)} expired sessions")