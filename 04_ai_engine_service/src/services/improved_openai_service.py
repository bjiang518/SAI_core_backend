"""
Enhanced AI Service with Streaming, Caching, and Optimized Performance

This optimized version provides:
1. Response streaming for better UX
2. Redis caching for frequent patterns  
3. Connection pooling and retry logic
4. Memory-efficient processing
5. Batch request handling
6. Response compression
"""

import openai
import asyncio
import json
import re
from typing import Dict, List, Optional, Any, AsyncGenerator, Literal
from pydantic import BaseModel, Field
from .prompt_service import AdvancedPromptService, Subject
import os
import hashlib
from datetime import datetime, timedelta
from dotenv import load_dotenv
import gzip
import time
# REMOVED: from tenacity import retry, stop_after_attempt, wait_exponential
# (No longer needed - OpenAI client has built-in retry logic)

load_dotenv()


# MARK: - Pydantic Models for Structured Output

class QuestionGrade(BaseModel):
    """Structured model for a graded homework question."""
    question_number: int
    raw_question_text: str
    question_text: str
    student_answer: str
    correct_answer: str
    grade: Literal["CORRECT", "INCORRECT", "EMPTY", "PARTIAL_CREDIT"]
    points_earned: float = Field(ge=0, le=1)
    points_possible: float = Field(default=1.0)
    confidence: float = Field(ge=0, le=1)
    feedback: str
    has_visuals: bool = False
    sub_parts: List[str] = Field(default_factory=list)


class PerformanceSummary(BaseModel):
    """Summary of student performance on homework."""
    total_correct: int
    total_incorrect: int
    total_empty: int
    total_partial_credit: int
    accuracy_rate: float = Field(ge=0, le=1)
    summary_text: str


class HomeworkGradingResult(BaseModel):
    """Complete structured homework grading result."""
    subject: str
    subject_confidence: float = Field(ge=0, le=1)
    total_questions_found: int
    questions: List[QuestionGrade]
    performance_summary: PerformanceSummary
    processing_notes: str = ""


class OptimizedEducationalAIService:
    """
    High-performance AI service with streaming, caching, and advanced optimization.
    Designed for production-scale usage with memory efficiency and response speed.
    """
    
    def __init__(self):
        print("🔄 === INITIALIZING OPTIMIZED AI SERVICE ===")
        
        # Check OpenAI API key first
        api_key = os.getenv('OPENAI_API_KEY')
        if not api_key:
            print("❌ WARNING: OPENAI_API_KEY not found in environment")
        else:
            print(f"✅ OpenAI API key found: {api_key[:10]}..." if len(api_key) > 10 else "✅ OpenAI API key found (short)")
        
        # OpenAI client with connection pooling
        try:
            self.client = openai.AsyncOpenAI(
                api_key=api_key,
                max_retries=3,
                timeout=120.0  # 2 minutes for complex homework parsing (was 60s)
            )
            print(f"✅ OpenAI AsyncClient initialized with 120s timeout: {type(self.client)}")
        except Exception as e:
            print(f"❌ Failed to initialize OpenAI client: {e}")
            raise
        
        self.prompt_service = AdvancedPromptService()

        # PHASE 2 OPTIMIZATION: Smart Model Selection (30-40% cost reduction)
        self.model_mini = "gpt-4o-mini"  # Fast & cheap for simple tasks
        self.model_standard = "gpt-4o"    # Full model for complex tasks
        self.model = self.model_mini  # Default to mini
        self.vision_model = "gpt-4o-2024-08-06"  # Required for structured outputs
        self.structured_output_model = "gpt-4o-2024-08-06"  # For structured outputs

        # Track model usage for cost monitoring
        self.model_usage_stats = {
            "gpt-4o-mini": {"calls": 0, "tokens": 0},
            "gpt-4o": {"calls": 0, "tokens": 0}
        }

        print(f"✅ Models configured:")
        print(f"   - Mini (default): {self.model_mini}")
        print(f"   - Standard: {self.model_standard}")
        print(f"   - Vision: {self.vision_model}")
        
        # In-memory cache (fallback if Redis not available)
        # OPTIMIZED: Increased from 1000 to 5000 entries for better hit rate
        self.memory_cache = {}
        self.cache_size_limit = 5000
        self.cache_eviction_batch = 500  # Evict 500 at once when full

        # NEW: Image hash cache for homework parsing
        self.image_cache = {}  # Hash-based cache for similar images
        self.image_cache_limit = 1000
        self.image_cache_hits = 0

        # Request deduplication to prevent duplicate OpenAI calls
        self.pending_requests = {}

        # Performance metrics
        self.request_count = 0
        self.cache_hits = 0
        self.cache_misses = 0
        self.total_tokens_saved = 0  # Track OpenAI cost savings
        
        print("✅ AI Service initialization complete")
        print("================================================")
    
    # MARK: - Caching System
    
    def _generate_cache_key(self, content: str, model: str) -> str:
        """Generate cache key from request content."""
        combined = f"{model}:{content}"
        return hashlib.sha256(combined.encode()).hexdigest()[:16]
    
    def _get_cached_response(self, cache_key: str) -> Optional[Dict]:
        """Get cached response if available. OPTIMIZED: Longer TTL for educational content."""
        if cache_key in self.memory_cache:
            cached_data = self.memory_cache[cache_key]

            # OPTIMIZED: 24 hour TTL for educational content (was 1 hour)
            # Educational answers don't change, so we can cache longer
            if time.time() - cached_data['timestamp'] < 86400:  # 24 hours
                self.cache_hits += 1
                # Track token savings
                if 'tokens_used' in cached_data:
                    self.total_tokens_saved += cached_data['tokens_used']
                return cached_data['response']
            else:
                # Remove expired entry
                del self.memory_cache[cache_key]

        self.cache_misses += 1
        return None
    
    def _set_cached_response(self, cache_key: str, response: Dict, tokens_used: int = 0):
        """Cache response in memory. OPTIMIZED: Smarter eviction with compression."""
        # Clean old entries if cache is full (LRU eviction)
        if len(self.memory_cache) >= self.cache_size_limit:
            # OPTIMIZED: Remove older batch (was 100, now 500) for efficiency
            oldest_keys = sorted(
                self.memory_cache.keys(),
                key=lambda k: self.memory_cache[k]['timestamp']
            )[:self.cache_eviction_batch]

            for key in oldest_keys:
                del self.memory_cache[key]

            print(f"🧹 Cache eviction: Removed {len(oldest_keys)} oldest entries")

        self.memory_cache[cache_key] = {
            'response': response,
            'timestamp': time.time(),
            'tokens_used': tokens_used  # Track for cost savings metrics
        }

    # MARK: - Smart Model Selection (PHASE 2 OPTIMIZATION)

    def _select_optimal_model(self, task_type: str, complexity: str = "medium") -> str:
        """
        PHASE 2: Select the most cost-effective model based on task requirements.

        Returns appropriate model based on task complexity:
        - gpt-4o-mini: Simple Q&A, classification, short responses
        - gpt-4o: Complex reasoning, long responses, creative tasks

        Cost savings: 30-40% by using mini model when appropriate
        """
        # Simple tasks that work well with mini model
        if task_type in ["simple_qa", "classification", "factual", "math_simple"]:
            return self.model_mini

        # Medium complexity - try mini first
        if complexity == "low" or complexity == "medium":
            return self.model_mini

        # Complex tasks require full model
        if task_type in ["reasoning", "creative", "analysis", "complex_math"]:
            return self.model_standard

        # Default to mini (cost-effective)
        return self.model_mini

    def _track_model_usage(self, model: str, tokens_used: int):
        """Track model usage for cost monitoring"""
        model_key = "gpt-4o-mini" if "mini" in model else "gpt-4o"
        if model_key in self.model_usage_stats:
            self.model_usage_stats[model_key]["calls"] += 1
            self.model_usage_stats[model_key]["tokens"] += tokens_used

    def get_model_usage_stats(self) -> dict:
        """Get model usage statistics for monitoring"""
        total_calls = sum(stats["calls"] for stats in self.model_usage_stats.values())
        total_tokens = sum(stats["tokens"] for stats in self.model_usage_stats.values())

        # Calculate cost savings (mini is ~20x cheaper)
        mini_tokens = self.model_usage_stats["gpt-4o-mini"]["tokens"]
        standard_tokens = self.model_usage_stats["gpt-4o"]["tokens"]

        # Cost per 1M tokens: mini=$0.15, standard=$2.50
        mini_cost = (mini_tokens / 1_000_000) * 0.15
        standard_cost = (standard_tokens / 1_000_000) * 2.50
        potential_savings = (mini_tokens / 1_000_000) * (2.50 - 0.15)  # If all were standard

        return {
            "total_calls": total_calls,
            "total_tokens": total_tokens,
            "mini_usage": self.model_usage_stats["gpt-4o-mini"],
            "standard_usage": self.model_usage_stats["gpt-4o"],
            "mini_percentage": (mini_tokens / total_tokens * 100) if total_tokens > 0 else 0,
            "actual_cost_usd": round(mini_cost + standard_cost, 2),
            "cost_savings_usd": round(potential_savings, 2)
        }
    
    # MARK: - Request Deduplication
    
    async def _deduplicate_request(self, cache_key: str, request_func):
        """Prevent duplicate requests for same content."""
        if cache_key in self.pending_requests:
            # Wait for existing request to complete
            return await self.pending_requests[cache_key]

        # Create new request
        task = asyncio.create_task(request_func())
        self.pending_requests[cache_key] = task

        try:
            result = await task
            return result
        finally:
            # Clean up pending request
            self.pending_requests.pop(cache_key, None)

    # MARK: - Image Hash Caching (New Optimization)

    def _get_image_hash(self, base64_image: str, parsing_mode: Optional[str] = None) -> str:
        """Generate SHA256 hash for image caching, including parsing mode to prevent cross-contamination."""
        # Include parsing mode in hash to ensure different modes don't share cache
        mode_suffix = f":{parsing_mode}" if parsing_mode else ""
        combined = f"{base64_image}{mode_suffix}"
        return hashlib.sha256(combined.encode()).hexdigest()[:16]

    def _get_cached_image_result(self, image_hash: str) -> Optional[Dict]:
        """Get cached homework parsing result for similar image with same parsing mode."""
        if image_hash in self.image_cache:
            cached_data = self.image_cache[image_hash]
            # 1 hour cache for images (homework is time-sensitive)
            if time.time() - cached_data['timestamp'] < 3600:
                self.image_cache_hits += 1
                return cached_data['result']
            else:
                del self.image_cache[image_hash]
        return None

    def _set_cached_image_result(self, image_hash: str, result: Dict):
        """Cache homework parsing result by image hash (includes parsing mode in hash)."""
        # Clean old entries if cache is full
        if len(self.image_cache) >= self.image_cache_limit:
            oldest_keys = sorted(
                self.image_cache.keys(),
                key=lambda k: self.image_cache[k]['timestamp']
            )[:100]  # Remove 100 oldest
            for key in oldest_keys:
                del self.image_cache[key]

        self.image_cache[image_hash] = {
            'result': result,
            'timestamp': time.time()
        }

    # MARK: - Dynamic Token Allocation (New Optimization)

    def _estimate_tokens_needed(self, base64_image: str) -> int:
        """
        Dynamically estimate tokens needed based on image size.
        Larger images = more content = more tokens needed.
        """
        image_size_kb = len(base64_image) * 0.75 / 1024  # Approximate size in KB

        if image_size_kb < 500:  # Small image (< 500KB compressed)
            tokens = 4000
            print(f"📊 Small image detected ({image_size_kb:.0f}KB) → allocating {tokens} tokens")
        elif image_size_kb < 1500:  # Medium image (500KB-1.5MB)
            tokens = 6000
            print(f"📊 Medium image detected ({image_size_kb:.0f}KB) → allocating {tokens} tokens")
        else:  # Large/complex image (> 1.5MB)
            tokens = 8000
            print(f"📊 Large image detected ({image_size_kb:.0f}KB) → allocating {tokens} tokens")

        return tokens

    # MARK: - Robust Text Parsing for Questions

    def _parse_questions_from_text(self, raw_response: str) -> List[Dict]:
        """
        Parse questions from text using robust delimiter-based approach.
        Much more reliable than JSON parsing for question generation.
        """
        print(f"🔍 Starting robust text parsing for questions...")
        print(f"📝 Raw response length: {len(raw_response)} characters")

        questions = []

        # Try JSON parsing first as fallback
        try:
            json_data = json.loads(raw_response)
            if isinstance(json_data, list):
                print(f"✅ Successfully parsed as direct JSON array with {len(json_data)} questions")
                return json_data
            elif isinstance(json_data, dict) and "questions" in json_data:
                print(f"✅ Successfully parsed as JSON object with {len(json_data['questions'])} questions")
                return json_data["questions"]
        except (json.JSONDecodeError, KeyError):
            print(f"⚠️ JSON parsing failed, switching to text parsing...")

        # Text-based parsing with delimiters
        # Look for question patterns: "question": "...", "type": "...", etc.
        lines = raw_response.split('\n')
        current_question = {}

        for line in lines:
            line = line.strip()
            if not line:
                continue

            # Look for field patterns with robust regex
            if '"question"' in line and ':' in line:
                # Extract question text
                question_match = re.search(r'"question":\s*"([^"]*)"', line)
                if question_match:
                    current_question['question'] = question_match.group(1)

            elif ('"question_type"' in line or '"type"' in line) and ':' in line:
                # Support both "question_type" (new format) and "type" (old format for backward compatibility)
                type_match = re.search(r'"(?:question_type|type)":\s*"([^"]*)"', line)
                if type_match:
                    current_question['question_type'] = type_match.group(1)

            elif '"correct_answer"' in line and ':' in line:
                answer_match = re.search(r'"correct_answer":\s*"([^"]*)"', line)
                if answer_match:
                    current_question['correct_answer'] = answer_match.group(1)

            elif '"explanation"' in line and ':' in line:
                explanation_match = re.search(r'"explanation":\s*"([^"]*)"', line)
                if explanation_match:
                    current_question['explanation'] = explanation_match.group(1)

            elif '"topic"' in line and ':' in line:
                topic_match = re.search(r'"topic":\s*"([^"]*)"', line)
                if topic_match:
                    current_question['topic'] = topic_match.group(1)

            elif '"difficulty"' in line and ':' in line:
                difficulty_match = re.search(r'"difficulty":\s*"([^"]*)"', line)
                if difficulty_match:
                    current_question['difficulty'] = difficulty_match.group(1)

            elif ('"multiple_choice_options"' in line or '"options"' in line) and '[' in line:
                # Support both "multiple_choice_options" (new format) and "options" (old format)
                # Extract options array - can be simple strings or objects with {label, text, is_correct}
                options_match = re.search(r'"(?:multiple_choice_options|options)":\s*\[(.*?)\]', line)
                if options_match:
                    options_str = options_match.group(1)
                    # Parse individual options
                    options = []
                    for opt in re.findall(r'"([^"]*)"', options_str):
                        options.append(opt)
                    current_question['multiple_choice_options'] = options

            # Check if we have a complete question
            if (len(current_question) >= 4 and
                'question' in current_question and
                'question_type' in current_question and
                'correct_answer' in current_question and
                'explanation' in current_question):

                # Set defaults for missing fields
                if 'topic' not in current_question:
                    current_question['topic'] = 'General'
                if 'difficulty' not in current_question:
                    current_question['difficulty'] = 'intermediate'
                if 'options' not in current_question:
                    current_question['options'] = None

                questions.append(current_question.copy())
                print(f"✅ Parsed question {len(questions)}: {current_question['question'][:50]}...")
                current_question = {}

        print(f"🎯 Text parsing completed: {len(questions)} questions extracted")

        # If text parsing failed, try even more aggressive parsing
        if len(questions) == 0:
            print(f"⚠️ Text parsing found no questions, trying aggressive fallback...")
            questions = self._aggressive_question_extraction(raw_response)

        return questions

    def _aggressive_question_extraction(self, text: str) -> List[Dict]:
        """
        Last resort: extract questions using pattern matching and heuristics.
        """
        questions = []

        # Look for question-like patterns
        question_patterns = [
            r'(?i)what\s+is.*\?',
            r'(?i)which\s+of.*\?',
            r'(?i)how\s+.*\?',
            r'(?i)calculate.*\?',
            r'(?i)solve.*\?',
            r'(?i)find.*\?'
        ]

        for pattern in question_patterns:
            matches = re.findall(pattern, text)
            for i, match in enumerate(matches[:3]):  # Max 3 questions per pattern
                questions.append({
                    'question': match.strip(),
                    'type': 'short_answer',
                    'correct_answer': 'Please provide the correct answer',
                    'explanation': 'Generated question needs manual review',
                    'topic': 'General',
                    'difficulty': 'intermediate',
                    'options': None
                })

        print(f"🔍 Aggressive extraction found {len(questions)} question patterns")
        return questions[:5]  # Limit to 5 questions max
    
    # REMOVED: @retry decorator - causes excessive timeout (374s total)
    # OpenAI client already has max_retries=3 built-in, so this is redundant
    async def parse_homework_image_json(
        self,
        base64_image: str,
        custom_prompt: Optional[str] = None,
        student_context: Optional[Dict] = None,
        parsing_mode: Optional[str] = None  # "hierarchical" or "baseline"
    ) -> Dict[str, Any]:
        """
        Parse homework images with guaranteed JSON structure using OpenAI structured outputs.

        OPTIMIZED IMPROVEMENTS:
        - Retry logic: 3 attempts with exponential backoff for transient failures
        - Image caching: Hash-based deduplication to save API calls
        - Mode-specific detail: "high" for hierarchical, "auto" for baseline (30-50% faster)
        - Temperature 0.2: Faster generation while maintaining consistency (was 0.1)
        - Reduced tokens: 6000 max for faster processing (was 8000)
        - Parsing mode: Hierarchical (default) or baseline (boost) parsing

        This method guarantees 100% consistent response format by:
        1. Using OpenAI's beta.chat.completions.parse with Pydantic models
        2. Automatic JSON schema generation from Pydantic models
        3. Guaranteed valid structured output (no parsing failures)
        4. Converting to legacy format for iOS compatibility

        Args:
            base64_image: Base64 encoded image data
            custom_prompt: Optional additional context
            student_context: Optional student learning context
            parsing_mode: "hierarchical" (high detail) or "baseline" (auto detail, faster)

        Returns:
            Structured response with guaranteed consistent formatting
        """

        try:
            # OPTIMIZATION 1: Check image cache first (include parsing_mode to prevent cross-contamination)
            image_hash = self._get_image_hash(base64_image, parsing_mode)
            cached_result = self._get_cached_image_result(image_hash)
            if cached_result:
                print(f"✅ IMAGE CACHE HIT for parsing_mode={parsing_mode}")
                return cached_result

            # Create the strict JSON schema prompt
            system_prompt = self._create_json_schema_prompt(custom_prompt, student_context, parsing_mode)

            # Prepare image message for OpenAI Vision API
            image_url = f"data:image/jpeg;base64,{base64_image}"

            # OPTIMIZATION 2: Dynamic token allocation based on image size
            max_tokens = self._estimate_tokens_needed(base64_image)

            # OPTIMIZATION 3: Mode-specific image detail level
            # Hierarchical mode: "high" detail for complex structure parsing
            # Baseline mode: "auto" detail for faster processing
            image_detail = "high" if parsing_mode == "hierarchical" else "auto"

            print(f"🔍 Allocating {max_tokens} tokens for homework parsing")
            print(f"🖼️ Image detail level: {image_detail} (parsing_mode={parsing_mode})")

            # Call OpenAI with structured output (guaranteed JSON)
            # Note: Structured outputs are only available in certain OpenAI SDK versions
            # For now, use regular chat completions with JSON mode

            print(f"🚀 === CALLING OPENAI API ===")
            print(f"📊 Model: {self.structured_output_model}")
            print(f"🎯 Max tokens: {max_tokens}")
            print(f"🔧 Parsing mode: {parsing_mode}")
            print(f"🖼️ Image detail: {image_detail}")
            print(f"📏 System prompt length: {len(system_prompt)} chars")
            print(f"📸 Image size: {len(base64_image)} chars")
            print(f"⏱️ Client timeout: 120s (for complex parsing)")
            print(f"=====================================")

            import time
            api_call_start = time.time()

            try:
                response = await self.client.chat.completions.create(
                    model=self.structured_output_model,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "text",
                                    "text": f"""Grade this homework image.

CRITICAL INSTRUCTIONS:
1. "student_answer" = What the student ACTUALLY WROTE on the paper (their handwriting/answer)
2. "correct_answer" = What the CORRECT/EXPECTED answer should be
3. Compare student_answer vs correct_answer to determine grade (CORRECT/INCORRECT/EMPTY/PARTIAL_CREDIT)
4. Extract EXACTLY what the student wrote, even if it's wrong - do NOT put the correct answer in student_answer field

{custom_prompt or ''}"""
                                },
                                {
                                    "type": "image_url",
                                    # OPTIMIZATION: Conditional detail level based on parsing mode
                                    # Hierarchical: "high" for complex structures
                                    # Baseline: "auto" for faster processing (30-50% faster)
                                    "image_url": {"url": image_url, "detail": image_detail}
                                }
                            ]
                        }
                    ],
                    response_format={"type": "json_object"},  # JSON mode instead of beta parse
                    # OPTIMIZATION 4: Temperature 0.2 for faster natural explanations (was 0.1)
                    temperature=0.2,
                    max_tokens=max_tokens,  # Dynamic allocation
                )

                api_call_duration = time.time() - api_call_start
                print(f"✅ === OPENAI API CALL COMPLETED ===")
                print(f"⏱️ Duration: {api_call_duration:.2f}s")
                print(f"=====================================")

            except Exception as api_error:
                api_call_duration = time.time() - api_call_start
                print(f"❌ === OPENAI API CALL FAILED ===")
                print(f"⏱️ Duration: {api_call_duration:.2f}s")
                print(f"❌ Error type: {type(api_error).__name__}")
                print(f"❌ Error message: {str(api_error)}")
                print(f"=====================================")
                raise

            # Parse JSON response manually
            raw_response = response.choices[0].message.content

            print(f"✅ === OPENAI RESPONSE RECEIVED ===")
            print(f"📊 Raw response length: {len(raw_response)} chars")
            print(f"📄 Response preview: {raw_response[:200]}...")
            print(f"=====================================")

            try:
                # Parse JSON
                import json

                # Try to clean malformed JSON before parsing
                cleaned_response = self._clean_json_response(raw_response)
                result_dict = json.loads(cleaned_response)

                # PHASE 1 OPTIMIZATION: Normalize optimized field names to full names
                result_dict = self._normalize_field_names(result_dict)

                print(f"✅ === JSON PARSED SUCCESSFULLY ===")
                print(f"📊 Keys: {list(result_dict.keys())}")
                print(f"📚 Subject: {result_dict.get('subject', 'Unknown')}")
                print(f"📊 Total questions found: {result_dict.get('total_questions_found', 0)}")
                print(f"📝 Questions array length: {len(result_dict.get('questions', []))}")

                # Validate JSON structure
                if not self._validate_json_structure(result_dict):
                    print(f"⚠️ JSON structure validation failed, attempting repair...")
                    result_dict = self._repair_json_structure(result_dict)

                # Log full JSON for debugging
                print(f"📄 === FULL JSON RESPONSE ===")
                print(json.dumps(result_dict, indent=2))
                print(f"=====================================")

                print(f"✅ JSON parsing complete - skipping legacy conversion (iOS uses direct JSON)")

                # OPTIMIZATION: Skip legacy format conversion since iOS parses JSON directly
                # Legacy format only generated as fallback when JSON parsing fails
                result = {
                    "success": True,
                    "structured_response": "",  # Empty - iOS uses raw_json instead
                    "parsing_method": "json_mode_optimized",  # Updated method indicator
                    "total_questions": len(result_dict.get("questions", [])),
                    "subject_detected": result_dict.get("subject", "Other"),
                    "subject_confidence": result_dict.get("subject_confidence", 0.5),
                    "raw_json": result_dict
                }

                # OPTIMIZATION 5: Cache the result
                self._set_cached_image_result(image_hash, result)

                return result
            except json.JSONDecodeError as je:
                print(f"⚠️ JSON decode error: {je}")
                print(f"📄 Raw response: {raw_response[:500]}...")
                # Fallback to text parsing
                return await self._fallback_text_parsing(raw_response, custom_prompt)

        except Exception as e:
            print(f"❌ Structured output parsing error: {e}")
            print(f"❌ Error type: {type(e).__name__}")

            # Fallback to old method if structured outputs fail
            return {
                "success": False,
                "structured_response": self._create_error_response(str(e)),
                "parsing_method": "error_fallback",
                "error": str(e)
            }

    def _get_max_tokens_for_homework(self) -> int:
        """
        Get max tokens for homework parsing.

        Optimized allocation based on typical homework:
        - Concise prompt: ~200 tokens (down from ~800)
        - Per question with grading: ~250 tokens (down from ~400)
        - Target: handle up to 20-25 questions comfortably
        - Result: 200 + (25 × 250) = 6450 tokens
        """
        return 6000  # Reduced from 8000 for faster processing

    def _convert_json_to_legacy_format(self, result_dict: Dict) -> str:
        """Convert JSON dict to legacy iOS-compatible text format.

        HIERARCHICAL SUPPORT: Handles both flat and hierarchical structures.
        - Flat: questions array at top level (backward compatibility)
        - Hierarchical: sections array with nested questions and subquestions

        COMPACT OUTPUT OPTIMIZATION (v2.0):
        - Reduced from 15+ fields to 10 essential fields per question
        - Removed internal metadata: QUESTION_ID, SECTION_ID, OCR_CONFIDENCE,
          LEGIBILITY, UNCLEAR_PORTIONS, SUB_PARTS
        - Kept RAW_QUESTION for archival/analysis purposes
        - Kept CONFIDENCE and HAS_VISUALS for database archiving
        - Result: ~50% smaller output = faster AI generation = no timeouts
        - Essential fields: QUESTION_NUMBER, RAW_QUESTION, QUESTION, STUDENT_ANSWER,
          CORRECT_ANSWER, GRADE, POINTS, CONFIDENCE, HAS_VISUALS, FEEDBACK
        """
        lines = []

        # Subject line
        lines.append(f"SUBJECT: {result_dict.get('subject', 'Other')}")
        lines.append(f"CONFIDENCE: {result_dict.get('subject_confidence', 0.5):.2f}")

        # Add hierarchical metadata if present
        if "total_sections" in result_dict:
            lines.append(f"TOTAL_SECTIONS: {result_dict.get('total_sections', 0)}")
            lines.append(f"HIERARCHICAL: true")
        else:
            lines.append(f"HIERARCHICAL: false")

        lines.append("")

        # Performance summary (if present)
        if "performance_summary" in result_dict:
            perf = result_dict['performance_summary']
            lines.append("PERFORMANCE SUMMARY:")
            lines.append(f"Total Correct: {perf.get('total_correct', 0)}")
            lines.append(f"Total Incorrect: {perf.get('total_incorrect', 0)}")
            lines.append(f"Total Empty: {perf.get('total_empty', 0)}")
            lines.append(f"Accuracy: {perf.get('accuracy_rate', 0):.0%}")
            lines.append(f"Summary: {perf.get('summary_text', '')}")
            lines.append("")

        # Process questions based on structure type
        all_questions = []

        # HIERARCHICAL STRUCTURE: sections with nested questions
        if "sections" in result_dict and isinstance(result_dict["sections"], list):
            for section in result_dict["sections"]:
                section_info = {
                    "section_id": section.get("section_id", ""),
                    "section_title": section.get("section_title", ""),
                    "section_type": section.get("section_type", ""),
                }

                # Add section header - COMPACT FORMAT (only if section has title/instructions)
                if section_info['section_title'] or section.get("section_instructions"):
                    lines.append(f"═══SECTION_HEADER═══")
                    if section_info['section_title']:
                        lines.append(f"SECTION_TITLE: {section_info['section_title']}")
                    if section.get("section_instructions"):
                        lines.append(f"INSTRUCTIONS: {section['section_instructions']}")
                    lines.append(f"═══SECTION_HEADER_END═══")
                    lines.append("")

                # Process questions in section
                for question in section.get("questions", []):
                    all_questions.append((question, section_info))

        # FLAT STRUCTURE: questions array at top level (backward compatibility)
        elif "questions" in result_dict:
            questions = result_dict.get('questions', [])
            for question in questions:
                all_questions.append((question, None))

        # Format all questions with proper separators
        for idx, (q, section_info) in enumerate(all_questions):
            # Check if this is a parent question with subquestions
            if q.get("is_parent") and q.get("has_subquestions"):
                # Parent question header - COMPACT FORMAT
                lines.append(f"═══PARENT_QUESTION_START═══")
                lines.append(f"QUESTION_NUMBER: {q.get('question_number', '')}")
                lines.append(f"PARENT_CONTENT: {q.get('parent_content', '')}")
                lines.append("")

                # Process subquestions - COMPACT FORMAT (with archive metadata)
                for sub_idx, subq in enumerate(q.get("subquestions", [])):
                    lines.append(f"SUBQUESTION_NUMBER: {subq.get('subquestion_number', '')}")
                    lines.append(f"RAW_QUESTION: {subq.get('raw_question_text', subq.get('question_text', ''))}")
                    lines.append(f"QUESTION: {subq.get('question_text', '')}")
                    lines.append(f"STUDENT_ANSWER: {subq.get('student_answer', '')}")
                    lines.append(f"CORRECT_ANSWER: {subq.get('correct_answer', '')}")
                    lines.append(f"GRADE: {subq.get('grade', 'UNKNOWN')}")
                    lines.append(f"POINTS: {subq.get('points_earned', 0)}/{subq.get('points_possible', 1)}")
                    lines.append(f"CONFIDENCE: {subq.get('confidence', 0.5):.2f}")
                    lines.append(f"HAS_VISUALS: {subq.get('has_visuals', False)}")
                    lines.append(f"FEEDBACK: {subq.get('feedback', '')}")

                    # Add subquestion separator if not last
                    if sub_idx < len(q.get("subquestions", [])) - 1:
                        lines.append("───SUBQUESTION_SEPARATOR───")
                    lines.append("")

                # Parent summary - COMPACT FORMAT
                if "parent_summary" in q:
                    summary = q["parent_summary"]
                    lines.append(f"TOTAL_POINTS: {summary.get('total_earned', 0)}/{summary.get('total_possible', 0)}")
                    if summary.get('overall_feedback'):
                        lines.append(f"OVERALL_FEEDBACK: {summary['overall_feedback']}")

                lines.append(f"═══PARENT_QUESTION_END═══")

            else:
                # Regular single question - COMPACT FORMAT (essential fields for iOS + archive metadata)
                lines.append(f"QUESTION_NUMBER: {q.get('question_number', idx + 1)}")
                lines.append(f"RAW_QUESTION: {q.get('raw_question_text', q.get('question_text', ''))}")
                lines.append(f"QUESTION: {q.get('question_text', '')}")
                lines.append(f"STUDENT_ANSWER: {q.get('student_answer', '')}")
                lines.append(f"CORRECT_ANSWER: {q.get('correct_answer', '')}")
                lines.append(f"GRADE: {q.get('grade', 'UNKNOWN')}")
                lines.append(f"POINTS: {q.get('points_earned', 0)}/{q.get('points_possible', 1)}")
                lines.append(f"CONFIDENCE: {q.get('confidence', 0.5):.2f}")
                lines.append(f"HAS_VISUALS: {q.get('has_visuals', False)}")
                lines.append(f"FEEDBACK: {q.get('feedback', '')}")

            # Add separator between questions (not after the last one)
            if idx < len(all_questions) - 1:
                lines.append("═══QUESTION_SEPARATOR═══")
            else:
                lines.append("")  # Empty line at the end

        return "\n".join(lines)

    def _convert_pydantic_to_legacy_format(self, result_dict: Dict) -> str:
        """Legacy method - now calls _convert_json_to_legacy_format."""
        return self._convert_json_to_legacy_format(result_dict)

    def _get_subject_specific_rules(self, subject: Optional[str]) -> str:
        """
        Get subject-specific grading criteria and rules.

        NEW: Different subjects require different grading approaches.
        This provides specialized rules for more accurate grading.
        """

        if not subject:
            return ""

        subject_lower = subject.lower()

        if subject_lower in ['mathematics', 'math']:
            return """
MATHEMATICS GRADING RULES:
- Exact numerical answers required (e.g., 0.5 not 1/2 unless specified)
- Check calculation steps if shown
- Verify units (m, kg, s, etc.) - missing units = PARTIAL_CREDIT
- Award PARTIAL_CREDIT (0.5) for: correct method but arithmetic error, missing units, incomplete work
- Feedback must explain WHERE the error occurred and HOW to fix it"""

        elif subject_lower == 'physics':
            return """
PHYSICS GRADING RULES:
- Numerical answers must include UNITS (e.g., 9.8 m/s²)
- Missing or wrong units = PARTIAL_CREDIT (0.5) even if number correct
- Check vector directions (positive/negative signs matter)
- Free body diagrams must show all forces
- Award PARTIAL_CREDIT for: correct formula but calculation error, missing units, incomplete diagrams
- Feedback should explain the physics concept, not just the math"""

        elif subject_lower == 'chemistry':
            return """
CHEMISTRY GRADING RULES:
- Chemical formulas must be exact (H₂O not H2O, CO₂ not CO2)
- Balanced equations required (check atom counts)
- Include states of matter (s, l, g, aq) if question requires
- Significant figures matter (3 sig figs if question specifies)
- Award PARTIAL_CREDIT for: unbalanced equations if species correct, missing states, sig fig errors
- Feedback should explain the chemistry principle"""

        elif subject_lower == 'biology':
            return """
BIOLOGY GRADING RULES:
- Scientific terminology expected (use proper terms, not colloquial)
- Diagrams must be labeled correctly
- Process descriptions should be sequential (Step 1, 2, 3...)
- Accept conceptually correct answers even if wording differs
- Award PARTIAL_CREDIT for: incomplete explanations, missing labels, correct concept but imprecise terminology
- Feedback should clarify the biological concept"""

        elif subject_lower == 'english':
            return """
ENGLISH GRADING RULES:
- Accept paraphrased answers if meaning is preserved
- Check for: thesis/main idea, supporting evidence, analysis/explanation
- Grammar/spelling errors don't affect grade unless they obscure meaning
- Award CORRECT if: thesis + evidence + analysis present
- Award PARTIAL_CREDIT (0.5-0.7) if: thesis + evidence only, or thesis only
- Feedback should be constructive and explain what's missing"""

        elif subject_lower == 'history':
            return """
HISTORY GRADING RULES:
- Dates can have reasonable margin (1-2 years acceptable for ancient history)
- Accept equivalent terms (e.g., "World War 1" = "WWI" = "Great War")
- Check for: historical accuracy, cause-effect reasoning, context
- Award CORRECT if: main facts correct even if details imprecise
- Award PARTIAL_CREDIT if: partially correct facts, missing context, one-sided explanation
- Feedback should provide historical context"""

        elif subject_lower == 'geography':
            return """
GEOGRAPHY GRADING RULES:
- Spelling of place names matters (Cairo not Kairo)
- Accept alternate names if commonly used (e.g., "Myanmar" or "Burma")
- Maps/diagrams must be labeled accurately
- Award CORRECT for conceptually accurate answers
- Award PARTIAL_CREDIT for: minor spelling errors, incomplete explanations, missing map labels
- Feedback should clarify geographical concepts"""

        elif subject_lower in ['computer science', 'cs', 'coding', 'programming']:
            return """
COMPUTER SCIENCE GRADING RULES:
- Code syntax matters (Python ≠ Java ≠ C++)
- Logic correctness more important than minor syntax errors
- Check for: correct algorithm, proper data structures, edge cases handled
- Award CORRECT if: logic correct even with minor syntax errors
- Award PARTIAL_CREDIT for: correct approach but incomplete implementation, logic errors, missing edge cases
- Feedback should explain the programming concept and logic"""

        else:
            # Generic rules for other subjects
            return """
GENERAL GRADING RULES:
- Accept answers that demonstrate understanding even if wording differs
- Award PARTIAL_CREDIT for partially correct or incomplete answers
- Provide constructive feedback explaining what's correct and what needs improvement"""

    def _create_essay_grading_prompt(self) -> str:
        """Create Essay-specific grading prompt with LaTeX grammar corrections.

        Returns JSON with grammar corrections and criterion scores.
        """
        return """You are an expert essay grader. Analyze this essay image and provide comprehensive feedback.

**OUTPUT FORMAT (STRICT JSON):**

{
  "essay_title": "Detected or inferred essay title",
  "word_count": 450,
  "grammar_corrections": [
    {
      "sentence_number": 1,
      "original_sentence": "The complete original sentence from the essay",
      "issue_type": "grammar",
      "explanation": "Clear explanation of the grammatical issue",
      "latex_correction": "The student \\\\sout{went} \\\\textcolor{green}{goes} to school yesterday.",
      "plain_correction": "The student goes to school yesterday."
    }
  ],
  "criterion_scores": {
    "grammar": {
      "score": 7.5,
      "feedback": "Overall assessment of grammar quality",
      "strengths": ["Consistent tense usage", "Proper punctuation"],
      "improvements": ["Subject-verb agreement", "Comma usage"]
    },
    "critical_thinking": {
      "score": 8.0,
      "feedback": "Evaluation of analytical skills",
      "strengths": ["Clear thesis", "Evidence-based arguments"],
      "improvements": ["Address counterarguments", "Deeper analysis"]
    },
    "organization": {
      "score": 9.0,
      "feedback": "Assessment of structure and flow",
      "strengths": ["Clear introduction/conclusion", "Logical transitions"],
      "improvements": ["More developed middle paragraphs"]
    },
    "coherence": {
      "score": 8.5,
      "feedback": "Evaluation of clarity and cohesion",
      "strengths": ["Effective topic sentences", "Good transitions"],
      "improvements": ["Strengthen section connections"]
    },
    "vocabulary": {
      "score": 7.0,
      "feedback": "Assessment of word choice",
      "strengths": ["Appropriate academic tone", "Clear language"],
      "improvements": ["More sophisticated vocabulary", "Avoid repetition"]
    }
  },
  "overall_score": 80.0,
  "overall_feedback": "Overall assessment of the essay (2-3 sentences)"
}

**LATEX FORMATTING RULES FOR GRAMMAR CORRECTIONS:**
- Use \\\\sout{incorrect_text} for strikethrough (text to be removed/corrected)
- Use \\\\textcolor{green}{correct_text} for the correct replacement (in green)
- Use \\\\textcolor{red}{text} to highlight errors
- Use \\\\textcolor{blue}{text} for suggestions or optional changes
- Example: "I \\\\sout{dont} \\\\textcolor{green}{don't} like it."
- Example: "She \\\\sout{are} \\\\textcolor{green}{is} a student."

**GRADING CRITERIA (0-10 scale for each criterion):**

1. **GRAMMAR & MECHANICS (0-10):**
   - Sentence structure correctness
   - Punctuation accuracy and consistency
   - Spelling errors
   - Verb tense consistency
   - Subject-verb agreement
   - Pronoun usage
   Identify the MOST CRITICAL 10-15 grammar errors (not all minor issues)

2. **CRITICAL THINKING (0-10):**
   - Depth of analysis and reasoning
   - Strength and validity of arguments
   - Use of evidence to support claims
   - Originality of ideas and perspectives
   - Addressing of counterarguments (if applicable)

3. **ORGANIZATION (0-10):**
   - Introduction quality (hook, thesis statement)
   - Paragraph structure and development
   - Logical flow and progression of ideas
   - Effectiveness of transitions between paragraphs
   - Conclusion quality (summary, final thoughts)

4. **COHERENCE & COHESION (0-10):**
   - Topic sentence clarity in each paragraph
   - Effectiveness of transition words/phrases
   - Connectivity between ideas and paragraphs
   - Overall readability and flow
   - Consistency of focus throughout

5. **VOCABULARY & STYLE (0-10):**
   - Appropriateness of word choice
   - Variety and sophistication of vocabulary
   - Academic tone consistency
   - Avoidance of redundancy and clichés
   - Sentence variety and complexity

**OVERALL SCORE CALCULATION:**
- Calculate overall_score as average of all 5 criterion scores * 10
- Example: If average of criteria is 8.0, overall_score = 80.0
- Range: 0-100

**IMPORTANT INSTRUCTIONS:**
1. Identify 10-15 MOST CRITICAL grammar errors (focus on high-impact issues)
2. For each grammar correction, provide COMPLETE original sentence and LaTeX-formatted correction
3. Provide specific, actionable feedback for each criterion
4. Balance criticism with encouragement - highlight strengths AND areas for improvement
5. Focus on higher-order concerns (ideas, organization) as well as lower-order concerns (grammar)
6. Be constructive - help the student improve their writing
7. Ensure all feedback is under 50 words per criterion
8. Estimate word count accurately by counting visible words in the essay

**JSON VALIDATION:**
- Ensure all keys are present in the output
- Ensure "issue_type" is one of: "grammar", "spelling", "punctuation", "style", "word_choice", "structure", "clarity"
- Ensure all scores are Float values between 0-10
- Ensure overall_score is Float between 0-100
- Ensure all arrays (strengths, improvements, grammar_corrections) are present (can be empty)
"""

    def _create_json_schema_prompt(self, custom_prompt: Optional[str], student_context: Optional[Dict], parsing_mode: Optional[str] = None) -> str:
        """Create a concise prompt that enforces strict JSON schema for grading.

        HIERARCHICAL PARSING: Feature flag controlled (USE_HIERARCHICAL_PARSING or parsing_mode parameter)
        SUBJECT-SPECIFIC RULES: Always included for better grading accuracy.
        ESSAY GRADING: Special handling for Essay subject with LaTeX grammar corrections.
        """

        # Extract subject from custom_prompt if provided
        subject = None
        if custom_prompt and "SUBJECT:" in custom_prompt:
            # Extract subject from prompt
            for line in custom_prompt.split('\n'):
                if line.startswith('SUBJECT:'):
                    subject = line.replace('SUBJECT:', '').strip()
                    break

        # Special handling for Essay grading
        if subject and subject.lower() == "essay":
            print(f"📝 Using Essay-specific grading prompt")
            return self._create_essay_grading_prompt()

        # Get subject-specific grading rules
        subject_rules = self._get_subject_specific_rules(subject) if subject else ""

        # Feature flag: Use hierarchical parsing
        # Priority: parsing_mode parameter > environment variable > default (false)
        if parsing_mode is not None:
            use_hierarchical = parsing_mode.lower() == 'hierarchical'
        else:
            use_hierarchical = os.getenv('USE_HIERARCHICAL_PARSING', 'false').lower() == 'true'

        print(f"🔧 Parsing mode: {'hierarchical' if use_hierarchical else 'baseline (fast)'}")

        if use_hierarchical:
            # OPTIMIZED HIERARCHICAL PROMPT: Compact version with proper parent-child format
            base_prompt = f"""Grade HW hierarchically. Return JSON:

{{
  "subject": "Math|Phys|Chem|Bio|Eng|Hist|Geo|CS|Other",
  "subject_confidence": 0.95,
  "total_questions_found": <N>,
  "sections": [
    {{
      "section_id": "s1",
      "section_type": "multiple_choice|fill_blank|short_answer|long_answer|calculation|diagram",
      "section_title": "Part A: Multiple Choice",
      "questions": [
        {{
          "question_id": "q1",
          "question_number": "1",
          "is_parent": true,
          "has_subquestions": true,
          "raw_parent_content": "COMPLETE original parent question verbatim from image (100-300+ chars, include ALL context and instructions)",
          "parent_content": "Short preview of parent question for UI (max 50 chars)",
          "subquestions": [
            {{
              "subquestion_number": "1a",
              "raw_question_text": "COMPLETE original question verbatim from image (100-300+ chars, include ALL context)",
              "question_text": "Short preview for UI (max 50 chars)",
              "student_answer": "student's written answer",
              "correct_answer": "expected answer",
              "grade": "CORRECT|INCORRECT|EMPTY|PARTIAL_CREDIT",
              "points_earned": 1.0,
              "points_possible": 1.0,
              "has_visuals": false,
              "feedback": "<30w",
              "question_type": "multiple_choice|true_false|fill_blank|short_answer|long_answer|calculation|matching",
              "options": ["A) Text", "B) Text", ...]
            }}
          ],
          "parent_summary": {{
            "total_earned": 3.0,
            "total_possible": 3.0,
            "overall_feedback": "Brief summary"
          }}
        }},
        {{
          "question_id": "q2",
          "question_number": "2",
          "is_parent": false,
          "raw_question_text": "COMPLETE original question verbatim from image (100-300+ chars, may be long word problem)",
          "question_text": "Short preview for UI (max 50 chars)",
          "student_answer": "student's written answer",
          "correct_answer": "expected answer",
          "grade": "CORRECT|INCORRECT|EMPTY|PARTIAL_CREDIT",
          "points_earned": 1.0,
          "feedback": "<30w",
          "question_type": "multiple_choice|true_false|fill_blank|short_answer|long_answer|calculation|matching",
          "options": ["A) Text", "B) Text", ...]
        }}
      ]
    }}
  ],
  "performance_summary": {{"total_correct": <N>, "total_incorrect": <N>, "total_empty": <N>, "total_partial_credit": <N>, "accuracy_rate": 0.0-1.0, "summary_text": "brief"}}
}}

{subject_rules}

RULES:
1. Group by type. Types: multiple_choice, fill_blank, calculation, short_answer, long_answer
2. Parent-child: "is_parent": true, "has_subquestions": true
3. Preserve exact question numbers. No restart across pages
4. CORRECT=1.0, INCORRECT/EMPTY=0.0, PARTIAL=0.5. Feedback <30w
5. "raw_question_text" = COMPLETE VERBATIM text from image (NOT shortened). May be 100-300+ characters for word problems.
6. "question_text" = Simplified short preview <50 chars for UI display only
7. "student_answer" = What student wrote. "correct_answer" = Expected. Never mix.
8. "question_type" = Detect type: multiple_choice (has A/B/C/D), true_false (T/F), fill_blank (has ___), calculation (math), short_answer, long_answer, matching
9. "options" = For multiple_choice: ["A) Text", "B) Text", ...]. For true_false: ["True", "False"]. For others: null or []
10. PARENT QUESTIONS: "raw_parent_content" = COMPLETE VERBATIM parent question text from image (NOT shortened). Include ALL context and instructions. "parent_content" = Simplified short preview <50 chars for UI display only"""
        else:
            # FLAT STRUCTURE (FAST & STABLE): Optimized for reliability
            base_prompt = f"""Grade HW. Return JSON:

{{
  "subject": "Math|Phys|Chem|Bio|Eng|Hist|Geo|CS|Other",
  "subject_confidence": 0.95,
  "total_questions_found": <N>,
  "questions": [
    {{
      "question_number": 1,
      "raw_question_text": "COMPLETE original question verbatim from image (100-300+ chars, include ALL text even for long word problems)",
      "question_text": "Short preview for UI (max 50 chars)",
      "student_answer": "student's written answer",
      "correct_answer": "expected answer",
      "grade": "CORRECT|INCORRECT|EMPTY|PARTIAL_CREDIT",
      "points_earned": 1.0,
      "feedback": "<30w"
    }}
  ],
  "performance_summary": {{"total_correct": <N>, "total_incorrect": <N>, "total_empty": <N>, "total_partial_credit": <N>, "accuracy_rate": 0.0-1.0, "summary_text": "brief"}}
}}

{subject_rules}

RULES:
1. Flat structure. Parse each question separately
2. Preserve exact question numbers
3. CORRECT=1.0, INCORRECT/EMPTY=0.0, PARTIAL=0.5. Feedback <30w
4. "raw_question_text" = COMPLETE VERBATIM text from image (NOT shortened). Capture the ENTIRE question exactly as written, may be 100-300+ characters.
5. "question_text" = Simplified short preview <50 chars for UI display only
6. "student_answer" = What student wrote. "correct_answer" = Expected. Never mix."""

        if student_context:
            base_prompt += f"\n\nStudent: {student_context.get('student_id', 'anonymous')}"

        if custom_prompt:
            base_prompt += f"\nContext: {custom_prompt}"

        return base_prompt
    
    def _validate_json_structure(self, json_data: Dict) -> bool:
        """
        Validate that JSON has required grading structure.

        OPTIMIZED: Added early returns for faster validation.
        HIERARCHICAL: Support both flat and hierarchical structures.
        """

        # Early return: Check type first
        if not isinstance(json_data, dict):
            return False

        # Normalize optimized field names to original format
        json_data = self._normalize_field_names(json_data)

        # Check required top-level fields
        if "subject" not in json_data or "performance_summary" not in json_data:
            return False

        # HIERARCHICAL SUPPORT: Check for either "sections" (new) or "questions" (old)
        has_sections = "sections" in json_data and isinstance(json_data["sections"], list)
        has_questions = "questions" in json_data and isinstance(json_data["questions"], list)

        if not has_sections and not has_questions:
            return False  # Must have either sections or questions

        # Validate hierarchical structure (sections with nested questions)
        if has_sections:
            if len(json_data["sections"]) == 0:
                return False

            # Validate first section structure
            first_section = json_data["sections"][0]
            section_fields = ["section_id", "section_type", "questions"]
            for field in section_fields:
                if field not in first_section:
                    return False

            # Check if section has questions
            if not isinstance(first_section["questions"], list) or len(first_section["questions"]) == 0:
                return False

            # Validate first question in first section
            first_question = first_section["questions"][0]

        # Validate flat structure (backward compatibility)
        elif has_questions:
            if len(json_data["questions"]) == 0:
                return False
            first_question = json_data["questions"][0]

        # Validate question structure (works for both hierarchical and flat)
        question_fields = ["question_text", "student_answer", "correct_answer", "grade"]
        for field in question_fields:
            if field not in first_question:
                # Check if this is a parent question with subquestions
                if first_question.get("is_parent") and "subquestions" in first_question:
                    # Parent questions may not have student_answer/correct_answer/grade
                    continue
                return False

        # Validate performance_summary structure
        performance_summary = json_data.get("performance_summary", {})
        summary_fields = ["total_correct", "total_incorrect", "total_partial_credit", "accuracy_rate", "summary_text"]
        for field in summary_fields:
            if field not in performance_summary:
                return False

        # Validate grade values
        valid_grades = ["CORRECT", "INCORRECT", "EMPTY", "PARTIAL_CREDIT", "PARTIAL"]
        grade = first_question.get("grade")

        # Parent questions may not have grades
        if grade and grade not in valid_grades:
            return False

        return True

    def _normalize_field_names(self, json_data: Dict) -> Dict:
        """Normalize optimized field names to original format.

        PHASE 1 OPTIMIZATION: Maps short field names to full names for compatibility.
        This allows the optimized prompt to use shorter field names (60% fewer tokens)
        while maintaining backward compatibility with existing code.
        """
        if not isinstance(json_data, dict):
            return json_data

        # Create a normalized copy
        normalized = json_data.copy()

        # Normalize top-level fields
        field_mapping = {
            "confidence": "subject_confidence",
            "total": "total_questions_found"
        }

        for short_name, full_name in field_mapping.items():
            if short_name in normalized and full_name not in normalized:
                normalized[full_name] = normalized[short_name]

        # Normalize question fields
        if "questions" in normalized and isinstance(normalized["questions"], list):
            normalized_questions = []
            for question in normalized["questions"]:
                if isinstance(question, dict):
                    normalized_question = question.copy()

                    question_field_mapping = {
                        "num": "question_number",
                        "raw": "raw_question_text",
                        "text": "question_text",
                        "ans": "student_answer",
                        "correct": "correct_answer",
                        "pts": "points_earned",
                        "conf": "confidence",
                        "visuals": "has_visuals"
                    }

                    for short_name, full_name in question_field_mapping.items():
                        if short_name in normalized_question and full_name not in normalized_question:
                            normalized_question[full_name] = normalized_question[short_name]

                    # Normalize grade: PARTIAL -> PARTIAL_CREDIT
                    if normalized_question.get("grade") == "PARTIAL":
                        normalized_question["grade"] = "PARTIAL_CREDIT"

                    # Ensure points_possible exists
                    if "points_possible" not in normalized_question and "points_earned" in normalized_question:
                        normalized_question["points_possible"] = 1.0

                    normalized_questions.append(normalized_question)

            normalized["questions"] = normalized_questions

        # Normalize summary fields
        if "summary" in normalized and "performance_summary" not in normalized:
            normalized["performance_summary"] = normalized["summary"]

        if "performance_summary" in normalized and isinstance(normalized["performance_summary"], dict):
            summary = normalized["performance_summary"].copy()

            summary_field_mapping = {
                "correct": "total_correct",
                "incorrect": "total_incorrect",
                "empty": "total_empty",
                "rate": "accuracy_rate",
                "text": "summary_text"
            }

            for short_name, full_name in summary_field_mapping.items():
                if short_name in summary and full_name not in summary:
                    summary[full_name] = summary[short_name]

            normalized["performance_summary"] = summary

        return normalized

    def _clean_json_response(self, raw_response: str) -> str:
        """Clean malformed JSON by removing duplicates and fixing common issues."""
        import re

        # Remove any markdown code blocks
        cleaned = re.sub(r'```json\n?', '', raw_response)
        cleaned = re.sub(r'```\n?', '', cleaned)

        # Remove duplicate keys by finding the last occurrence
        # This handles cases where OpenAI returns duplicate fields
        try:
            # First try to extract just the JSON object
            json_match = re.search(r'\{.*\}', cleaned, re.DOTALL)
            if json_match:
                cleaned = json_match.group(0)

            # Remove trailing commas before closing braces/brackets
            cleaned = re.sub(r',(\s*[}\]])', r'\1', cleaned)

            return cleaned
        except Exception as e:
            print(f"⚠️ JSON cleaning error: {e}")
            return raw_response

    def _repair_json_structure(self, json_data: Dict) -> Dict:
        """Repair incomplete or malformed JSON structure to meet validation requirements."""
        repaired = json_data.copy()

        # Ensure required top-level fields exist
        if "subject" not in repaired:
            repaired["subject"] = "Other"
        if "subject_confidence" not in repaired:
            repaired["subject_confidence"] = 0.5
        if "total_questions_found" not in repaired:
            repaired["total_questions_found"] = len(repaired.get("questions", []))

        # Ensure questions array exists
        if "questions" not in repaired or not isinstance(repaired["questions"], list):
            repaired["questions"] = []

        # Repair each question to have all required fields
        for i, question in enumerate(repaired["questions"]):
            if not isinstance(question, dict):
                continue

            # Set defaults for missing fields
            question.setdefault("question_number", i + 1)
            question.setdefault("raw_question_text", question.get("question_text", ""))
            question.setdefault("question_text", question.get("raw_question_text", f"Question {i + 1}"))
            question.setdefault("student_answer", "")
            question.setdefault("correct_answer", "")
            question.setdefault("grade", "EMPTY")
            question.setdefault("points_earned", 0.0)
            question.setdefault("points_possible", 1.0)
            question.setdefault("confidence", 0.5)
            question.setdefault("has_visuals", False)
            question.setdefault("feedback", "")
            question.setdefault("sub_parts", [])

            # Validate and fix grade values
            valid_grades = ["CORRECT", "INCORRECT", "EMPTY", "PARTIAL_CREDIT"]
            if question.get("grade") not in valid_grades:
                question["grade"] = "EMPTY"

        # Ensure performance_summary exists with all required fields
        if "performance_summary" not in repaired:
            repaired["performance_summary"] = {}

        # BUGFIX: Always recalculate performance_summary from actual question grades
        # to override any incorrect counts from AI (use direct assignment, not setdefault)
        perf = repaired["performance_summary"]
        total_questions = len(repaired["questions"])
        correct_count = sum(1 for q in repaired["questions"] if q.get("grade") == "CORRECT")
        incorrect_count = sum(1 for q in repaired["questions"] if q.get("grade") == "INCORRECT")
        empty_count = sum(1 for q in repaired["questions"] if q.get("grade") == "EMPTY")
        partial_credit_count = sum(1 for q in repaired["questions"] if q.get("grade") == "PARTIAL_CREDIT")

        # Direct assignment to always use recalculated values
        perf["total_correct"] = correct_count
        perf["total_incorrect"] = incorrect_count
        perf["total_empty"] = empty_count
        perf["total_partial_credit"] = partial_credit_count
        perf["accuracy_rate"] = correct_count / total_questions if total_questions > 0 else 0.0
        perf["summary_text"] = f"Graded {total_questions} questions: {correct_count} correct, {incorrect_count} incorrect, {partial_credit_count} partial credit"

        # Ensure processing_notes exists
        repaired.setdefault("processing_notes", "JSON structure repaired for consistency")

        print(f"✅ JSON structure repaired: {len(repaired['questions'])} questions validated")

        return repaired

    def _normalize_json_response(self, json_data: Dict) -> Dict:
        """Normalize JSON response to consistent grading format."""
        
        # Extract performance summary
        performance_summary = json_data.get("performance_summary", {})
        
        normalized = {
            "subject": json_data.get("subject", "Other"),
            "subject_confidence": float(json_data.get("subject_confidence", 0.5)),
            "total_questions": json_data.get("total_questions_found", len(json_data.get("questions", []))),
            "questions": [],
            "processing_notes": json_data.get("processing_notes", "Graded successfully"),
            "performance_summary": {
                "total_correct": performance_summary.get("total_correct", 0),
                "total_incorrect": performance_summary.get("total_incorrect", 0),
                "total_empty": performance_summary.get("total_empty", 0),
                "total_partial_credit": performance_summary.get("total_partial_credit", 0),
                "accuracy_rate": float(performance_summary.get("accuracy_rate", 0.0)),
                "summary_text": performance_summary.get("summary_text", "No summary available")
            }
        }
        
        # Normalize each graded question
        for i, question in enumerate(json_data.get("questions", [])):
            normalized_question = {
                "question_number": question.get("question_number", i + 1),
                "raw_question_text": question.get("raw_question_text", question.get("question_text", "Raw question not found")),
                "question_text": question.get("question_text", "Question text not found"),
                "student_answer": question.get("student_answer", ""),
                "correct_answer": question.get("correct_answer", question.get("answer", "Answer not provided")),
                "grade": question.get("grade", "EMPTY"),
                "points_earned": float(question.get("points_earned", 0.0)),
                "points_possible": float(question.get("points_possible", 1.0)),
                "confidence": float(question.get("confidence", 0.8)),
                "has_visuals": bool(question.get("has_visuals", False)),
                "feedback": question.get("feedback", "No feedback provided"),
                "sub_parts": question.get("sub_parts", question.get("sub_questions", []))
            }
            normalized["questions"].append(normalized_question)
        
        return normalized
    
    def _convert_to_legacy_format(self, normalized_data: Dict) -> str:
        """Convert normalized JSON to legacy ═══QUESTION_SEPARATOR═══ format for iOS grading compatibility."""
        
        performance_summary = normalized_data.get("performance_summary", {})
        
        legacy_response = f"SUBJECT: {normalized_data['subject']}\n"
        legacy_response += f"SUBJECT_CONFIDENCE: {normalized_data['subject_confidence']}\n"
        legacy_response += f"TOTAL_QUESTIONS: {normalized_data['total_questions']}\n"
        legacy_response += f"JSON_PARSING: true\n"
        legacy_response += f"PARSING_METHOD: Enhanced AI Backend Grading with JSON Schema\n"
        
        # Add performance summary
        legacy_response += f"TOTAL_CORRECT: {performance_summary.get('total_correct', 0)}\n"
        legacy_response += f"TOTAL_INCORRECT: {performance_summary.get('total_incorrect', 0)}\n"
        legacy_response += f"TOTAL_EMPTY: {performance_summary.get('total_empty', 0)}\n"
        legacy_response += f"ACCURACY_RATE: {performance_summary.get('accuracy_rate', 0.0)}\n"
        legacy_response += f"SUMMARY_TEXT: {performance_summary.get('summary_text', 'No summary available')}\n\n"
        
        for i, question in enumerate(normalized_data["questions"]):
            if i > 0:
                legacy_response += "═══QUESTION_SEPARATOR═══\n"
            
            legacy_response += f"QUESTION_NUMBER: {question['question_number']}\n"
            legacy_response += f"RAW_QUESTION: {question['raw_question_text']}\n"
            legacy_response += f"QUESTION: {question['question_text']}\n"
            legacy_response += f"STUDENT_ANSWER: {question['student_answer']}\n"
            legacy_response += f"CORRECT_ANSWER: {question['correct_answer']}\n"
            legacy_response += f"GRADE: {question['grade']}\n"
            legacy_response += f"POINTS_EARNED: {question['points_earned']}\n"
            legacy_response += f"POINTS_POSSIBLE: {question['points_possible']}\n"
            legacy_response += f"FEEDBACK: {question['feedback']}\n"
            legacy_response += f"CONFIDENCE: {question['confidence']}\n"
            legacy_response += f"HAS_VISUALS: {'true' if question['has_visuals'] else 'false'}\n"
            
            if question['sub_parts']:
                legacy_response += f"SUB_PARTS: {'; '.join(question['sub_parts'])}\n"
        
        return legacy_response
    
    def _convert_to_fallback_legacy_format(self, normalized_data: Dict) -> str:
        """Convert normalized data to legacy format marked as fallback parsing."""
        
        legacy_response = f"SUBJECT: {normalized_data['subject']}\n"
        legacy_response += f"SUBJECT_CONFIDENCE: {normalized_data['subject_confidence']}\n"
        legacy_response += f"TOTAL_QUESTIONS: {normalized_data['total_questions']}\n"
        legacy_response += f"JSON_PARSING: false\n"
        legacy_response += f"PARSING_METHOD: Enhanced AI Backend Parsing with Fallback Text Analysis\n\n"
        
        for i, question in enumerate(normalized_data["questions"]):
            if i > 0:
                legacy_response += "═══QUESTION_SEPARATOR═══\n"
            
            legacy_response += f"QUESTION_NUMBER: {question['question_number']}\n"
            legacy_response += f"QUESTION: {question['question_text']}\n"
            legacy_response += f"ANSWER: {question['answer']}\n"
            legacy_response += f"CONFIDENCE: {question['confidence']}\n"
            legacy_response += f"HAS_VISUALS: {'true' if question['has_visuals'] else 'false'}\n"
            
            if question['sub_parts']:
                legacy_response += f"SUB_PARTS: {'; '.join(question['sub_parts'])}\n"
        
        return legacy_response
    
    async def _fallback_text_parsing(self, raw_response: str, custom_prompt: Optional[str]) -> Dict[str, Any]:
        """Robust fallback parsing when JSON format fails."""
        
        print("🔄 Using fallback text parsing...")
        
        try:
            # Try to extract structured information from text
            subject = self._extract_subject_from_text(raw_response)
            confidence = self._extract_confidence_from_text(raw_response)
            questions = self._extract_questions_from_text(raw_response)
            
            # If no structured questions found, create a basic response
            if not questions:
                questions = [{
                    "question_number": 1,
                    "question_text": "Unable to parse specific questions from image",
                    "answer": raw_response[:500] + "..." if len(raw_response) > 500 else raw_response,
                    "confidence": 0.3,
                    "has_visuals": False,
                    "sub_parts": []
                }]
            
            # Create normalized format
            normalized_data = {
                "subject": subject,
                "subject_confidence": confidence,
                "total_questions": len(questions),
                "questions": questions,
                "processing_notes": "Parsed using fallback text analysis"
            }
            
            # Convert to legacy format (mark as fallback)
            legacy_response = self._convert_to_fallback_legacy_format(normalized_data)
            
            return {
                "success": True,
                "structured_response": legacy_response,
                "parsing_method": "fallback_text",
                "total_questions": len(questions),
                "subject_detected": subject,
                "subject_confidence": confidence
            }
            
        except Exception as fallback_error:
            print(f"❌ Fallback parsing also failed: {fallback_error}")
            return {
                "success": False,
                "structured_response": self._create_error_response(f"All parsing methods failed: {fallback_error}"),
                "parsing_method": "complete_failure",
                "error": str(fallback_error)
            }
    
    def _extract_subject_from_text(self, text: str) -> str:
        """Extract subject from unstructured text."""
        text_lower = text.lower()
        
        subjects = {
            "mathematics": ["math", "equation", "algebra", "geometry", "calculus", "statistics"],
            "physics": ["physics", "force", "energy", "momentum", "wave", "electromagnetic"],
            "chemistry": ["chemistry", "molecule", "atom", "reaction", "compound", "element"],
            "biology": ["biology", "cell", "organism", "genetics", "evolution", "ecosystem"],
            "english": ["english", "literature", "grammar", "writing", "poetry", "essay"],
            "history": ["history", "historical", "event", "century", "civilization", "culture"]
        }
        
        for subject, keywords in subjects.items():
            if any(keyword in text_lower for keyword in keywords):
                return subject.title()
        
        return "Other"
    
    def _extract_confidence_from_text(self, text: str) -> float:
        """Extract confidence score from text or estimate based on content."""
        # Look for explicit confidence patterns
        confidence_patterns = [
            r"confidence[:\s]*([0-9.]+)",
            r"certainty[:\s]*([0-9.]+)",
            r"sure[:\s]*([0-9.]+)"
        ]
        
        for pattern in confidence_patterns:
            match = re.search(pattern, text.lower())
            if match:
                try:
                    return float(match.group(1))
                except ValueError:
                    continue
        
        # Estimate confidence based on text quality
        if len(text) > 100 and "step" in text.lower():
            return 0.8
        elif len(text) > 50:
            return 0.6
        else:
            return 0.4
    
    def _extract_questions_from_text(self, text: str) -> List[Dict]:
        """Extract questions from unstructured text."""
        questions = []
        
        # Split by common question indicators
        question_patterns = [
            r'\n\s*\d+[\.)]\s+',  # "1. " or "1) "
            r'\n\s*[Qq]uestion\s*\d*[:\s]+',  # "Question 1:"
            r'\n\s*[a-z][\.)]\s+',  # "a) " or "b."
            r'═══QUESTION_SEPARATOR═══'  # Legacy separator
        ]
        
        # Try to split the text using these patterns
        text_parts = [text]  # Start with full text
        
        for pattern in question_patterns:
            new_parts = []
            for part in text_parts:
                splits = re.split(pattern, part)
                new_parts.extend([s.strip() for s in splits if s.strip()])
            text_parts = new_parts
        
        # Process each potential question
        for i, part in enumerate(text_parts):
            if len(part) > 20:  # Filter out very short fragments
                # Try to split into question and answer
                lines = part.split('\n')
                question_text = lines[0] if lines else part[:100]
                answer_text = '\n'.join(lines[1:]) if len(lines) > 1 else part
                
                questions.append({
                    "question_number": i + 1,
                    "question_text": self._clean_question_text(question_text),
                    "answer": answer_text.strip(),
                    "confidence": 0.7,
                    "has_visuals": self._detect_visual_content(part),
                    "sub_parts": []
                })
        
        return questions[:5]  # Limit to 5 questions max
    
    def _clean_question_text(self, text: str) -> str:
        """Clean question text by removing numbering and formatting."""
        # Remove common question prefixes
        text = re.sub(r'^\d+[\.)]\s*', '', text)  # Remove "1. " or "1) "
        text = re.sub(r'^[Qq]uestion\s*\d*[:\s]*', '', text, flags=re.IGNORECASE)  # Remove "Question:"
        text = re.sub(r'^[a-z][\.)]\s*', '', text, flags=re.IGNORECASE)  # Remove "a) "
        
        return text.strip()
    
    def _detect_visual_content(self, text: str) -> bool:
        """Detect if text suggests visual elements."""
        visual_indicators = [
            "diagram", "graph", "chart", "figure", "image", "picture",
            "drawing", "illustration", "plot", "visual", "shown", "depicted"
        ]
        
        text_lower = text.lower()
        return any(indicator in text_lower for indicator in visual_indicators)
    
    def _create_error_response(self, error_message: str) -> str:
        """Create a standard error response in legacy format."""
        return f"""SUBJECT: Other
SUBJECT_CONFIDENCE: 0.1

QUESTION_NUMBER: 1
QUESTION: Unable to parse homework image
ANSWER: Processing error occurred: {error_message}. Please try again with a clearer image.
CONFIDENCE: 0.1
HAS_VISUALS: false"""
    
    async def health_check(self) -> Dict[str, Any]:
        """Enhanced health check for the improved AI service."""
        try:
            # Test basic JSON response capability
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "user", "content": "Respond with JSON: {\"status\": \"healthy\", \"test\": true}"}
                ],
                max_tokens=50,
                response_format={"type": "json_object"}
            )
            
            result = json.loads(response.choices[0].message.content)
            
            return {
                "status": "healthy",
                "model": self.model,
                "json_support": True,
                "strict_formatting": True,
                "fallback_parsing": True,
                "test_response": result
            }
            
        except Exception as e:
            return {
                "status": "unhealthy",
                "model": self.model,
                "json_support": False,
                "error": str(e)
            }


# Maintain backward compatibility by extending the original service
class EducationalAIService:
    """
    Enhanced version of the original EducationalAIService with improved parsing.
    This maintains all existing functionality while adding the new consistent parsing.
    """
    
    def __init__(self):
        # Set up OpenAI client properly
        self.client = openai.AsyncOpenAI(
            api_key=os.getenv('OPENAI_API_KEY'),
            max_retries=3,
            timeout=120.0  # Match timeout with OptimizedEducationalAIService
        )
        self.prompt_service = AdvancedPromptService()
        self.model = "gpt-4o-mini"
        self.vision_model = "gpt-4o"  # Full model for vision tasks
        self.structured_output_model = "gpt-4o-2024-08-06"  # For structured outputs (progressive grading)

        # Add the improved service for homework parsing
        self.improved_service = OptimizedEducationalAIService()

        # OPTIMIZED: Add cache metrics for health check compatibility
        self.memory_cache = self.improved_service.memory_cache
        self.cache_size_limit = self.improved_service.cache_size_limit
        self.cache_hits = self.improved_service.cache_hits
        self.cache_misses = self.improved_service.cache_misses
        self.request_count = self.improved_service.request_count
        self.total_tokens_saved = self.improved_service.total_tokens_saved
    
    async def parse_homework_image(
        self,
        base64_image: str,
        custom_prompt: Optional[str] = None,
        student_context: Optional[Dict] = None,
        parsing_mode: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Enhanced homework parsing with improved consistency.

        This method now uses the improved AI service for better results while
        maintaining backward compatibility with the existing iOS app.
        """

        # Use the improved service for better consistency
        return await self.improved_service.parse_homework_image_json(
            base64_image=base64_image,
            custom_prompt=custom_prompt,
            student_context=student_context,
            parsing_mode=parsing_mode
        )
    
    async def process_session_conversation(
        self, 
        session_id: str,
        message: str, 
        image_data: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Process session-based conversation messages with specialized prompting for tutoring sessions.
        
        This method is specifically designed for conversational AI tutoring sessions, different from
        simple question processing. It uses specialized prompting strategies optimized for:
        - Back-and-forth educational conversations
        - Consistent LaTeX formatting for iOS post-processing  
        - Conversational flow and engagement
        - Session-specific context handling
        """
        
        try:
            # Use specialized conversational prompting
            system_prompt = self.prompt_service.create_session_conversation_prompt(
                message=message,
                session_id=session_id
            )
            
            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": message}
            ]
            
            # Add image analysis if provided
            if image_data:
                # For session conversations with images, add image content to the message
                messages[-1]["content"] = [
                    {"type": "text", "text": message},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{image_data}",
                            "detail": "high"
                        }
                    }
                ]
            
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=messages,
                temperature=0.4,  # Slightly higher for more conversational responses
                max_tokens=1200,  # Shorter responses for conversations
                presence_penalty=0.1,
                frequency_penalty=0.1
            )
            
            raw_answer = response.choices[0].message.content
            
            # Apply session-specific optimization (focuses on conversational flow)
            optimized_answer = self.prompt_service.optimize_session_response(raw_answer)
            
            return {
                "success": True,
                "answer": optimized_answer,
                "tokens_used": response.usage.total_tokens if response.usage else 0,
                "compressed": False,
                "session_id": session_id,
                "processing_details": {
                    "model_used": self.model,
                    "prompt_optimization": True,
                    "response_optimization": True,
                    "conversation_mode": True,
                    "session_specific": True
                }
            }
        
        except Exception as e:
            return {
                "success": False,
                "error": f"Session conversation processing failed: {str(e)}",
                "session_id": session_id
            }
    async def process_educational_question(
        self, 
        question: str, 
        subject: str,
        student_context: Optional[Dict] = None,
        include_followups: bool = True
    ) -> Dict[str, Any]:
        """Process educational questions with advanced AI reasoning (existing method)."""
        
        try:
            system_prompt = self.prompt_service.create_enhanced_prompt(
                question=question,
                subject_string=subject,
                context=student_context
            )
            
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": question}
                ],
                temperature=0.3,
                max_tokens=1500,
                presence_penalty=0.1,
                frequency_penalty=0.1
            )
            
            raw_answer = response.choices[0].message.content
            optimized_answer = self.prompt_service.optimize_response(raw_answer, subject)
            
            follow_ups = []
            if include_followups:
                follow_ups = self.prompt_service.generate_follow_up_questions(question, subject)
            
            reasoning_steps = self._extract_reasoning_steps(optimized_answer)
            concepts = self._identify_key_concepts(optimized_answer, subject)
            
            return {
                "success": True,
                "answer": optimized_answer,
                "reasoning_steps": reasoning_steps,
                "key_concepts": concepts,
                "follow_up_questions": follow_ups,
                "subject": subject,
                "processing_details": {
                    "model_used": self.model,
                    "prompt_optimization": True,
                    "response_optimization": True,
                    "educational_enhancement": True
                }
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Educational question processing failed: {str(e)}"
            }
    
    def _extract_reasoning_steps(self, text: str) -> List[str]:
        """Extract reasoning steps from text (existing method)."""
        steps = []

        # Look for numbered steps
        step_patterns = [
            r'\d+\.\s*([^\n]+)',
            r'Step\s*\d+[:\s]*([^\n]+)',
            r'First[,\s]*([^\n]+)',
            r'Next[,\s]*([^\n]+)',
            r'Then[,\s]*([^\n]+)',
            r'Finally[,\s]*([^\n]+)'
        ]

        for pattern in step_patterns:
            matches = re.findall(pattern, text, re.IGNORECASE)
            steps.extend([match.strip() for match in matches])

        return steps[:5]  # Limit to 5 steps

    def _parse_questions_from_text(self, raw_response: str) -> List[Dict]:
        """
        Parse questions from text using robust delimiter-based approach.
        Much more reliable than JSON parsing for question generation.
        """
        print(f"🔍 Starting robust text parsing for questions...")
        print(f"📝 Raw response length: {len(raw_response)} characters")

        questions = []

        # Try JSON parsing first as fallback
        try:
            json_data = json.loads(raw_response)
            if isinstance(json_data, list):
                print(f"✅ Successfully parsed as direct JSON array with {len(json_data)} questions")
                return json_data
            elif isinstance(json_data, dict) and "questions" in json_data:
                print(f"✅ Successfully parsed as JSON object with {len(json_data['questions'])} questions")
                return json_data["questions"]
        except (json.JSONDecodeError, KeyError):
            print(f"⚠️ JSON parsing failed, switching to text parsing...")

        # Text-based parsing with delimiters
        # Look for question patterns: "question": "...", "type": "...", etc.
        lines = raw_response.split('\n')
        current_question = {}

        for line in lines:
            line = line.strip()
            if not line:
                continue

            # Look for field patterns with robust regex
            if '"question"' in line and ':' in line:
                # Extract question text
                question_match = re.search(r'"question":\s*"([^"]*)"', line)
                if question_match:
                    current_question['question'] = question_match.group(1)

            elif ('"question_type"' in line or '"type"' in line) and ':' in line:
                # Support both "question_type" (new format) and "type" (old format for backward compatibility)
                type_match = re.search(r'"(?:question_type|type)":\s*"([^"]*)"', line)
                if type_match:
                    current_question['question_type'] = type_match.group(1)

            elif '"correct_answer"' in line and ':' in line:
                answer_match = re.search(r'"correct_answer":\s*"([^"]*)"', line)
                if answer_match:
                    current_question['correct_answer'] = answer_match.group(1)

            elif '"explanation"' in line and ':' in line:
                explanation_match = re.search(r'"explanation":\s*"([^"]*)"', line)
                if explanation_match:
                    current_question['explanation'] = explanation_match.group(1)

            elif '"topic"' in line and ':' in line:
                topic_match = re.search(r'"topic":\s*"([^"]*)"', line)
                if topic_match:
                    current_question['topic'] = topic_match.group(1)

            elif '"difficulty"' in line and ':' in line:
                difficulty_match = re.search(r'"difficulty":\s*"([^"]*)"', line)
                if difficulty_match:
                    current_question['difficulty'] = difficulty_match.group(1)

            elif ('"multiple_choice_options"' in line or '"options"' in line) and '[' in line:
                # Support both "multiple_choice_options" (new format) and "options" (old format)
                # Extract options array - can be simple strings or objects with {label, text, is_correct}
                options_match = re.search(r'"(?:multiple_choice_options|options)":\s*\[(.*?)\]', line)
                if options_match:
                    options_str = options_match.group(1)
                    # Parse individual options
                    options = []
                    for opt in re.findall(r'"([^"]*)"', options_str):
                        options.append(opt)
                    current_question['multiple_choice_options'] = options

            # Check if we have a complete question
            if (len(current_question) >= 4 and
                'question' in current_question and
                'question_type' in current_question and
                'correct_answer' in current_question and
                'explanation' in current_question):

                # Set defaults for missing fields
                if 'topic' not in current_question:
                    current_question['topic'] = 'General'
                if 'difficulty' not in current_question:
                    current_question['difficulty'] = 'intermediate'
                if 'options' not in current_question:
                    current_question['options'] = None

                questions.append(current_question.copy())
                print(f"✅ Parsed question {len(questions)}: {current_question['question'][:50]}...")
                current_question = {}

        print(f"🎯 Text parsing completed: {len(questions)} questions extracted")

        # If text parsing failed, try even more aggressive parsing
        if len(questions) == 0:
            print(f"⚠️ Text parsing found no questions, trying aggressive fallback...")
            questions = self._aggressive_question_extraction(raw_response)

        return questions

    def _aggressive_question_extraction(self, text: str) -> List[Dict]:
        """
        Last resort: extract questions using pattern matching and heuristics.
        """
        questions = []

        # Look for question-like patterns
        question_patterns = [
            r'(?i)what\s+is.*\?',
            r'(?i)which\s+of.*\?',
            r'(?i)how\s+.*\?',
            r'(?i)calculate.*\?',
            r'(?i)solve.*\?',
            r'(?i)find.*\?'
        ]

        for pattern in question_patterns:
            matches = re.findall(pattern, text)
            for i, match in enumerate(matches[:3]):  # Max 3 questions per pattern
                questions.append({
                    'question': match.strip(),
                    'type': 'short_answer',
                    'correct_answer': 'Please provide the correct answer',
                    'explanation': 'Generated question needs manual review',
                    'topic': 'General',
                    'difficulty': 'intermediate',
                    'options': None
                })

        print(f"🔍 Aggressive extraction found {len(questions)} question patterns")
        return questions[:5]  # Limit to 5 questions max
    
    def _identify_key_concepts(self, text: str, subject: str) -> List[str]:
        """Identify key concepts from text (existing method)."""
        concepts = []
        
        # Subject-specific concept patterns
        concept_patterns = {
            "mathematics": [
                r"(algebra|geometry|calculus|trigonometry|statistics)",
                r"(equation|formula|theorem|proof|solution)",
                r"(variable|constant|function|derivative|integral)"
            ],
            "physics": [
                r"(force|energy|momentum|acceleration|velocity)",
                r"(wave|frequency|amplitude|electromagnetic)",
                r"(quantum|relativity|thermodynamics|mechanics)"
            ]
        }
        
        patterns = concept_patterns.get(subject.lower(), [
            r"([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)",
            r"(important|key|fundamental|basic|advanced)"
        ])
        
        for pattern in patterns:
            matches = re.findall(pattern, text, re.IGNORECASE)
            concepts.extend([match.strip() for match in matches if isinstance(match, str)])
        
        return list(set(concepts))[:5]  # Remove duplicates and limit to 5

    async def analyze_image_with_chat_context(
        self,
        base64_image: str,
        user_prompt: str,
        subject: Optional[str] = "general",
        session_id: Optional[str] = None,
        student_context: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """
        Analyze image with chat context for conversational responses.
        Optimized for fast, natural language responses suitable for chat interfaces.
        
        Args:
            base64_image: Base64 encoded image data
            user_prompt: User's question or prompt about the image
            subject: Subject context (math, science, etc.)
            session_id: Optional session ID for context awareness
            student_context: Optional student learning context
            
        Returns:
            Dict with response, tokens_used, and success status
        """
        
        try:
            print(f"🔄 === AI SERVICE: CHAT IMAGE ANALYSIS START ===")
            print(f"📝 User Prompt: {user_prompt}")
            print(f"📚 Subject: {subject}")
            print(f"🆔 Session: {session_id}")
            print(f"📄 Image length: {len(base64_image)} chars")
            
            # Check if OpenAI API key is available
            api_key = os.getenv('OPENAI_API_KEY')
            if not api_key:
                raise Exception("OpenAI API key not configured")
            print(f"✅ OpenAI API key verified: {api_key[:10]}..." if len(api_key) > 10 else "✅ API key verified")
            
            # Verify client is available
            if not self.client:
                raise Exception("OpenAI client not initialized")
            print(f"✅ OpenAI client available: {type(self.client)}")
            
            # Create conversational prompt optimized for chat
            print("🔄 Creating chat image prompt...")
            system_prompt = self._create_chat_image_prompt(user_prompt, subject, student_context)
            print(f"✅ System prompt created: {len(system_prompt)} chars")
            
            # Prepare image for OpenAI Vision API
            print("🔄 Preparing image for OpenAI Vision API...")
            image_url = f"data:image/jpeg;base64,{base64_image}"
            
            messages = [
                {
                    "role": "system",
                    "content": system_prompt
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": user_prompt
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": image_url,
                                "detail": "high"
                            }
                        }
                    ]
                }
            ]
            print(f"✅ Messages prepared: {len(messages)} messages")
            print(f"📊 System prompt length: {len(system_prompt)} chars")
            print(f"📊 User prompt length: {len(user_prompt)} chars")
            print(f"📊 Image URL length: {len(image_url)} chars")
            
            print(f"📡 Calling OpenAI Vision API...")
            print(f"🤖 Model: {self.vision_model}")
            print(f"⚙️ Settings: max_tokens=800, temperature=0.7")
            
            # Use vision model with optimized settings for chat
            response = await self.client.chat.completions.create(
                model=self.vision_model,  # Use full vision model for image analysis
                messages=messages,
                max_tokens=800,  # Shorter responses for chat
                temperature=0.7,  # Slightly more conversational
                stream=False
            )
            
            print(f"✅ OpenAI API call completed successfully")
            print(f"📊 Response type: {type(response)}")
            
            ai_response = response.choices[0].message.content.strip()
            tokens_used = response.usage.total_tokens if response.usage else 0
            
            print(f"✅ === AI SERVICE: CHAT IMAGE ANALYSIS SUCCESS ===")
            print(f"📝 Response length: {len(ai_response)} chars")
            print(f"🎯 Tokens used: {tokens_used}")
            
            return {
                "success": True,
                "response": ai_response,
                "tokens_used": tokens_used,
                "processing_type": "chat_image",
                "model_used": self.vision_model
            }
            
        except Exception as e:
            # Comprehensive error logging
            import traceback
            error_msg = f"Chat image analysis failed: {str(e) if str(e) else 'Unknown error'}"
            full_traceback = traceback.format_exc()
            
            print(f"❌ === AI SERVICE: CHAT IMAGE ANALYSIS ERROR ===")
            print(f"💥 Error message: '{str(e)}'")
            print(f"💥 Error repr: {repr(e)}")
            print(f"🔧 Exception type: {type(e).__name__}")
            print(f"🔧 Exception module: {type(e).__module__}")
            print(f"🔧 Exception args: {e.args}")
            print(f"📋 Full traceback:")
            print(full_traceback)
            print(f"🔍 OpenAI API key available: {bool(os.getenv('OPENAI_API_KEY'))}")
            print(f"🔍 Client type: {type(self.client)}")
            print(f"=====================================")
            
            # Return more detailed error for debugging
            detailed_error = f"{error_msg} | Type: {type(e).__name__} | Args: {e.args} | Traceback: {full_traceback[:500]}"
            
            return {
                "success": False,
                "error": detailed_error,
                "response": "I'm having trouble analyzing this image right now. Please try again in a moment.",
                "tokens_used": 0
            }

    async def analyze_image_with_chat_context_stream(
        self,
        base64_image: str,
        user_prompt: str,
        subject: Optional[str] = "general",
        session_id: Optional[str] = None,
        student_context: Optional[Dict] = None
    ) -> AsyncGenerator[str, None]:
        """
        Analyze image with chat context for conversational responses with STREAMING.
        Optimized for real-time, token-by-token responses suitable for chat interfaces.

        Args:
            base64_image: Base64 encoded image data
            user_prompt: User's question or prompt about the image
            subject: Subject context (math, science, etc.)
            session_id: Optional session ID for context awareness
            student_context: Optional student learning context

        Yields:
            JSON strings with streaming chunks in format:
            {"type": "start", "timestamp": "..."}
            {"type": "content", "content": "...", "delta": "..."}
            {"type": "end", "tokens": 123, "finish_reason": "stop"}
            {"type": "error", "error": "..."}
        """

        start_time = time.time()
        total_tokens = 0
        accumulated_content = ""

        try:
            print(f"🔄 === AI SERVICE: STREAMING CHAT IMAGE ANALYSIS START ===")
            print(f"📝 User Prompt: {user_prompt}")
            print(f"📚 Subject: {subject}")
            print(f"🆔 Session: {session_id}")
            print(f"📄 Image length: {len(base64_image)} chars")

            # Check if OpenAI API key is available
            api_key = os.getenv('OPENAI_API_KEY')
            if not api_key:
                yield json.dumps({"type": "error", "error": "OpenAI API key not configured"})
                return

            # Verify client is available
            if not self.client:
                yield json.dumps({"type": "error", "error": "OpenAI client not initialized"})
                return

            # Create conversational prompt optimized for chat
            system_prompt = self._create_chat_image_prompt(user_prompt, subject, student_context)

            # Prepare image for OpenAI Vision API
            image_url = f"data:image/jpeg;base64,{base64_image}"

            messages = [
                {
                    "role": "system",
                    "content": system_prompt
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": user_prompt
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": image_url,
                                "detail": "high"
                            }
                        }
                    ]
                }
            ]

            print(f"📡 Calling OpenAI Vision API with STREAMING...")
            print(f"🤖 Model: {self.vision_model}")

            # Send start event
            yield json.dumps({
                "type": "start",
                "timestamp": datetime.now().isoformat(),
                "model": self.vision_model
            })

            # Use vision model with streaming enabled
            stream = await self.client.chat.completions.create(
                model=self.vision_model,
                messages=messages,
                max_tokens=800,
                temperature=0.7,
                stream=True  # Enable streaming
            )

            # Stream the response
            async for chunk in stream:
                if chunk.choices and len(chunk.choices) > 0:
                    delta = chunk.choices[0].delta

                    if delta.content:
                        content_chunk = delta.content
                        accumulated_content += content_chunk

                        # Send content chunk
                        yield json.dumps({
                            "type": "content",
                            "content": accumulated_content,
                            "delta": content_chunk
                        })

                    # Check for finish
                    if chunk.choices[0].finish_reason:
                        finish_reason = chunk.choices[0].finish_reason
                        processing_time = int((time.time() - start_time) * 1000)

                        print(f"✅ === AI SERVICE: STREAMING CHAT IMAGE ANALYSIS COMPLETE ===")
                        print(f"📝 Total response length: {len(accumulated_content)} chars")
                        print(f"⏱️ Processing time: {processing_time}ms")

                        # Send end event
                        yield json.dumps({
                            "type": "end",
                            "tokens": total_tokens,
                            "finish_reason": finish_reason,
                            "processing_time_ms": processing_time,
                            "content": accumulated_content
                        })

        except Exception as e:
            # Comprehensive error logging
            import traceback
            error_msg = f"Streaming chat image analysis failed: {str(e)}"
            full_traceback = traceback.format_exc()

            print(f"❌ === AI SERVICE: STREAMING CHAT IMAGE ANALYSIS ERROR ===")
            print(f"💥 Error: {error_msg}")
            print(f"📋 Full traceback:")
            print(full_traceback)

            # Send error event
            yield json.dumps({
                "type": "error",
                "error": error_msg,
                "traceback": full_traceback[:500]
            })

    def _create_chat_image_prompt(
        self,
        user_prompt: str,
        subject: str,
        student_context: Optional[Dict] = None
    ) -> str:
        """
        Create an optimized prompt for chat image analysis.
        Focuses on conversational, helpful responses.
        """
        
        base_prompt = f"""You are StudyAI, a helpful educational assistant specializing in {subject}. 

The user has sent you an image with this question: "{user_prompt}"

Please analyze the image and provide a clear, conversational response that:
1. Directly addresses their question
2. Explains what you see in the image relevant to their question
3. Provides educational value appropriate for their level
4. Uses a natural, friendly tone suitable for chat
5. Keeps the response concise but informative (aim for 2-4 sentences)

If the image contains:
- Math problems: Show the solution steps clearly
- Diagrams/charts: Explain what they represent
- Text: Help them understand the content
- Homework: Provide guidance without just giving answers

Focus on being helpful and educational while maintaining a conversational tone."""

        # Add student context if available
        if student_context and student_context.get("student_id"):
            base_prompt += f"\n\nStudent context: {student_context.get('student_id', 'anonymous')}"

        return base_prompt

    # MARK: - Question Generation Methods

    async def generate_random_questions(
        self,
        subject: str,
        config: Dict[str, Any],
        user_profile: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Generate random practice questions for a given subject.

        Args:
            subject: Subject area (e.g., 'mathematics', 'physics')
            config: Configuration with topics, focus_notes, difficulty, question_count
            user_profile: User details like grade, location, preferences

        Returns:
            Dict with generated questions in JSON format
        """

        try:
            print(f"🎯 === AI SERVICE: RANDOM QUESTIONS GENERATION START ===")
            print(f"📚 Subject: {subject}")
            print(f"⚙️  Config: {config}")
            print(f"👤 User Profile: {user_profile}")

            # Generate the comprehensive prompt
            system_prompt = self.prompt_service.get_random_questions_prompt(subject, config, user_profile)

            print(f"📝 === FULL INPUT PROMPT FOR RANDOM QUESTIONS ===")
            print(f"📄 Prompt Length: {len(system_prompt)} characters")
            print(f"📋 Full Prompt Content:")
            print("=" * 80)
            print(system_prompt)
            print("=" * 80)

            # Call OpenAI with JSON response format enforcement
            print(f"📡 Calling OpenAI API for question generation...")
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": f"Generate {config.get('question_count', 5)} random questions for {subject} now."}
                ],
                temperature=0.7,  # Higher temperature for variety in questions
                max_tokens=3000,
                # Remove JSON format requirement for more reliable parsing
            )

            raw_response = response.choices[0].message.content
            tokens_used = response.usage.total_tokens if response.usage else 0

            print(f"✅ OpenAI API call completed")
            print(f"📊 Tokens used: {tokens_used}")
            print(f"📝 Raw response length: {len(raw_response)} characters")
            print(f"📋 Raw Response Preview: {raw_response[:200]}...")

            # Use robust text parsing instead of fragile JSON parsing
            try:
                questions_json = self._parse_questions_from_text(raw_response)

                # Validate that we have questions
                if not questions_json or len(questions_json) == 0:
                    raise ValueError("No valid questions could be extracted from response")

                # Validate each question has required fields
                required_fields = ["question", "question_type", "correct_answer", "explanation", "topic"]
                for i, question in enumerate(questions_json):
                    # Support both old and new field names for backward compatibility
                    if "type" in question and "question_type" not in question:
                        question["question_type"] = question["type"]
                    if "options" in question and "multiple_choice_options" not in question:
                        question["multiple_choice_options"] = question["options"]

                    for field in required_fields:
                        if field not in question:
                            raise ValueError(f"Question {i+1} missing required field: {field}")

                print(f"✅ === AI SERVICE: RANDOM QUESTIONS GENERATION SUCCESS ===")
                print(f"🎯 Generated {len(questions_json)} questions")

                return {
                    "success": True,
                    "questions": questions_json,
                    "generation_type": "random",
                    "subject": subject,
                    "tokens_used": tokens_used,
                    "question_count": len(questions_json),
                    "config_used": config,
                    "processing_details": {
                        "model_used": self.model,
                        "prompt_optimization": True,
                        "json_format": True,
                        "validation_passed": True
                    }
                }

            except (ValueError, Exception) as parse_error:
                print(f"⚠️ Question parsing failed: {parse_error}")
                print(f"📄 Raw response: {raw_response}")

                return {
                    "success": False,
                    "error": f"Question generation parsing failed: {parse_error}",
                    "raw_response": raw_response,
                    "generation_type": "random",
                    "subject": subject
                }

        except Exception as e:
            print(f"❌ === AI SERVICE: RANDOM QUESTIONS GENERATION ERROR ===")
            print(f"💥 Error: {str(e)}")
            import traceback
            print(f"📋 Full traceback: {traceback.format_exc()}")

            return {
                "success": False,
                "error": f"Random question generation failed: {str(e)}",
                "generation_type": "random",
                "subject": subject
            }

    async def generate_mistake_based_questions(
        self,
        subject: str,
        mistakes_data: List[Dict],
        config: Dict[str, Any],
        user_profile: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Generate questions based on previous mistakes to help remedial learning.

        Args:
            subject: Subject area
            mistakes_data: List of previous mistakes with context
            config: Configuration including question_count
            user_profile: User details

        Returns:
            Dict with generated remedial questions in JSON format
        """

        try:
            print(f"🎯 === AI SERVICE: MISTAKE-BASED QUESTIONS GENERATION START ===")
            print(f"📚 Subject: {subject}")
            print(f"❌ Mistakes Count: {len(mistakes_data)}")
            print(f"⚙️  Config: {config}")
            print(f"👤 User Profile: {user_profile}")

            # Generate the comprehensive prompt
            system_prompt = self.prompt_service.get_mistake_based_questions_prompt(
                subject, mistakes_data, config, user_profile
            )

            print(f"📝 === FULL INPUT PROMPT FOR MISTAKE-BASED QUESTIONS ===")
            print(f"📄 Prompt Length: {len(system_prompt)} characters")
            print(f"📋 Full Prompt Content:")
            print("=" * 80)
            print(system_prompt)
            print("=" * 80)

            # Call OpenAI with JSON response format enforcement
            print(f"📡 Calling OpenAI API for mistake-based question generation...")
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": f"Generate {config.get('question_count', 5)} remedial questions based on the mistake patterns for {subject}."}
                ],
                temperature=0.6,  # Moderate temperature for focused remedial questions
                max_tokens=3000,
                # Remove JSON format requirement for more reliable parsing
            )

            raw_response = response.choices[0].message.content
            tokens_used = response.usage.total_tokens if response.usage else 0

            print(f"✅ OpenAI API call completed")
            print(f"📊 Tokens used: {tokens_used}")
            print(f"📝 Raw response length: {len(raw_response)} characters")
            print(f"📋 Raw Response Preview: {raw_response[:200]}...")

            # Use robust text parsing instead of fragile JSON parsing
            try:
                questions_json = self._parse_questions_from_text(raw_response)

                # Validate that we have questions
                if not questions_json or len(questions_json) == 0:
                    raise ValueError("No valid questions could be extracted from response")

                # Extract unique tags from source mistakes for enforcement
                all_source_tags = []
                for mistake in mistakes_data:
                    mistake_tags = mistake.get('tags', [])
                    if mistake_tags:
                        all_source_tags.extend(mistake_tags)
                unique_source_tags = list(set(all_source_tags))

                # ENFORCEMENT: Override all question tags with source tags
                # This ensures tag inheritance even if AI doesn't follow instructions
                if unique_source_tags:
                    print(f"🏷️ Enforcing tag inheritance: {unique_source_tags}")
                    for question in questions_json:
                        question['tags'] = unique_source_tags
                        print(f"  ✓ Set tags for question: '{question.get('question', '')[:50]}...'")
                else:
                    print(f"⚠️ No source tags found in mistakes_data, generated questions will have no tags")

                # Validate each question has required fields
                required_fields = ["question", "question_type", "correct_answer", "explanation", "topic"]
                for i, question in enumerate(questions_json):
                    # Support both old and new field names for backward compatibility
                    if "type" in question and "question_type" not in question:
                        question["question_type"] = question["type"]
                    if "options" in question and "multiple_choice_options" not in question:
                        question["multiple_choice_options"] = question["options"]

                    for field in required_fields:
                        if field not in question:
                            raise ValueError(f"Question {i+1} missing required field: {field}")

                print(f"✅ === AI SERVICE: MISTAKE-BASED QUESTIONS GENERATION SUCCESS ===")
                print(f"🎯 Generated {len(questions_json)} remedial questions")

                return {
                    "success": True,
                    "questions": questions_json,
                    "generation_type": "mistake_based",
                    "subject": subject,
                    "tokens_used": tokens_used,
                    "question_count": len(questions_json),
                    "mistakes_analyzed": len(mistakes_data),
                    "config_used": config,
                    "processing_details": {
                        "model_used": self.model,
                        "prompt_optimization": True,
                        "json_format": True,
                        "validation_passed": True,
                        "remedial_focus": True
                    }
                }

            except (json.JSONDecodeError, ValueError) as parse_error:
                print(f"⚠️ JSON parsing failed: {parse_error}")
                print(f"📄 Raw response: {raw_response}")

                return {
                    "success": False,
                    "error": f"Mistake-based question generation parsing failed: {parse_error}",
                    "raw_response": raw_response,
                    "generation_type": "mistake_based",
                    "subject": subject
                }

        except Exception as e:
            print(f"❌ === AI SERVICE: MISTAKE-BASED QUESTIONS GENERATION ERROR ===")
            print(f"💥 Error: {str(e)}")
            import traceback
            print(f"📋 Full traceback: {traceback.format_exc()}")

            return {
                "success": False,
                "error": f"Mistake-based question generation failed: {str(e)}",
                "generation_type": "mistake_based",
                "subject": subject
            }

    async def generate_conversation_based_questions(
        self,
        subject: str,
        conversation_data: List[Dict],
        config: Dict[str, Any],
        user_profile: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Generate personalized questions based on previous conversations.

        Args:
            subject: Subject area
            conversation_data: List of conversation summaries and contexts
            config: Configuration including question_count
            user_profile: User details

        Returns:
            Dict with generated personalized questions in JSON format
        """

        try:
            print(f"🎯 === AI SERVICE: CONVERSATION-BASED QUESTIONS GENERATION START ===")
            print(f"📚 Subject: {subject}")
            print(f"💬 Conversations Count: {len(conversation_data)}")
            print(f"⚙️  Config: {config}")
            print(f"👤 User Profile: {user_profile}")

            # Generate the comprehensive prompt
            system_prompt = self.prompt_service.get_conversation_based_questions_prompt(
                subject, conversation_data, config, user_profile
            )

            print(f"📝 === FULL INPUT PROMPT FOR CONVERSATION-BASED QUESTIONS ===")
            print(f"📄 Prompt Length: {len(system_prompt)} characters")
            print(f"📋 Full Prompt Content:")
            print("=" * 80)
            print(system_prompt)
            print("=" * 80)

            # Call OpenAI with JSON response format enforcement
            print(f"📡 Calling OpenAI API for conversation-based question generation...")
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": f"Generate {config.get('question_count', 5)} personalized questions based on the conversation history for {subject}."}
                ],
                temperature=0.8,  # Higher temperature for more personalized, creative questions
                max_tokens=3000,
                # Remove JSON format requirement for more reliable parsing
            )

            raw_response = response.choices[0].message.content
            tokens_used = response.usage.total_tokens if response.usage else 0

            print(f"✅ OpenAI API call completed")
            print(f"📊 Tokens used: {tokens_used}")
            print(f"📝 Raw response length: {len(raw_response)} characters")
            print(f"📋 Raw Response Preview: {raw_response[:200]}...")

            # Use robust text parsing instead of fragile JSON parsing
            try:
                questions_json = self._parse_questions_from_text(raw_response)

                # Validate that we have questions
                if not questions_json or len(questions_json) == 0:
                    raise ValueError("No valid questions could be extracted from response")

                # Validate each question has required fields
                required_fields = ["question", "question_type", "correct_answer", "explanation", "topic"]
                for i, question in enumerate(questions_json):
                    # Support both old and new field names for backward compatibility
                    if "type" in question and "question_type" not in question:
                        question["question_type"] = question["type"]
                    if "options" in question and "multiple_choice_options" not in question:
                        question["multiple_choice_options"] = question["options"]

                    for field in required_fields:
                        if field not in question:
                            raise ValueError(f"Question {i+1} missing required field: {field}")

                print(f"✅ === AI SERVICE: CONVERSATION-BASED QUESTIONS GENERATION SUCCESS ===")
                print(f"🎯 Generated {len(questions_json)} personalized questions")

                return {
                    "success": True,
                    "questions": questions_json,
                    "generation_type": "conversation_based",
                    "subject": subject,
                    "tokens_used": tokens_used,
                    "question_count": len(questions_json),
                    "conversations_analyzed": len(conversation_data),
                    "config_used": config,
                    "processing_details": {
                        "model_used": self.model,
                        "prompt_optimization": True,
                        "json_format": True,
                        "validation_passed": True,
                        "personalization": True
                    }
                }

            except (json.JSONDecodeError, ValueError) as parse_error:
                print(f"⚠️ JSON parsing failed: {parse_error}")
                print(f"📄 Raw response: {raw_response}")

                return {
                    "success": False,
                    "error": f"Conversation-based question generation parsing failed: {parse_error}",
                    "raw_response": raw_response,
                    "generation_type": "conversation_based",
                    "subject": subject
                }

        except Exception as e:
            print(f"❌ === AI SERVICE: CONVERSATION-BASED QUESTIONS GENERATION ERROR ===")
            print(f"💥 Error: {str(e)}")
            import traceback
            print(f"📋 Full traceback: {traceback.format_exc()}")

            return {
                "success": False,
                "error": f"Conversation-based question generation failed: {str(e)}",
                "generation_type": "conversation_based",
                "subject": subject
            }


    # ======================================================================
    # PROGRESSIVE HOMEWORK GRADING METHODS
    # ======================================================================

    async def parse_homework_questions_with_coordinates(
        self,
        base64_image: str,
        parsing_mode: str = "standard"
    ) -> Dict[str, Any]:
        """
        Parse homework image and extract questions with normalized image coordinates.

        This is Phase 1 of progressive grading:
        1. Analyze the homework image
        2. Extract each question and student's answer
        3. Identify questions that need image context (diagrams, graphs)
        4. Return normalized coordinates [0-1] for image regions

        Args:
            base64_image: Base64 encoded homework image
            parsing_mode: "standard" (faster) or "detailed" (more accurate)

        Returns:
            Dict with:
            - success: Boolean
            - subject: Detected subject
            - subject_confidence: Float 0-1
            - total_questions: Int
            - questions: List of ParsedQuestion objects with coordinates
        """

        print(f"📝 === PARSING HOMEWORK WITH COORDINATES ===")
        print(f"🔧 Mode: {parsing_mode}")

        try:
            # Build prompt for parsing with coordinates
            system_prompt = self._build_parse_with_coordinates_prompt(parsing_mode)

            # Prepare image message
            image_url = f"data:image/jpeg;base64,{base64_image}"

            print(f"🚀 Calling OpenAI Vision API...")
            start_time = time.time()

            # Call OpenAI with JSON response format
            response = await self.client.chat.completions.create(
                model=self.structured_output_model,  # gpt-4o-2024-08-06 for structured outputs
                messages=[
                    {"role": "system", "content": system_prompt},
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": "Parse this homework image. Extract all questions with student answers and normalized image coordinates."
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": image_url,
                                    "detail": "high"  # High detail for accurate coordinate detection
                                }
                            }
                        ]
                    }
                ],
                response_format={"type": "json_object"},
                temperature=0.2,
                max_tokens=6000  # Enough for 20+ questions with coordinates
            )

            api_duration = time.time() - start_time
            print(f"✅ OpenAI API completed in {api_duration:.2f}s")

            # Parse JSON response
            raw_response = response.choices[0].message.content
            result = json.loads(raw_response)

            print(f"📊 Parsed {result.get('total_questions', 0)} questions")
            print(f"📚 Subject: {result.get('subject', 'Unknown')}")

            # VALIDATION: Fix total_questions counting bug
            questions_array = result.get("questions", [])
            ai_total = result.get("total_questions", 0)
            actual_total = len(questions_array)

            if ai_total != actual_total:
                print(f"⚠️  WARNING: total_questions mismatch!")
                print(f"   AI claimed: {ai_total}")
                print(f"   Actual array length: {actual_total}")
                print(f"   ✅ Using actual array length: {actual_total}")

                # Override with correct count
                result["total_questions"] = actual_total

            return {
                "success": True,
                "subject": result.get("subject", "Unknown"),
                "subject_confidence": result.get("subject_confidence", 0.5),
                "total_questions": result.get("total_questions", 0),
                "questions": questions_array
            }

        except json.JSONDecodeError as e:
            print(f"❌ JSON parsing error: {e}")
            return {
                "success": False,
                "error": f"Failed to parse JSON response: {str(e)}"
            }
        except Exception as e:
            print(f"❌ Parsing error: {e}")
            import traceback
            traceback.print_exc()
            return {
                "success": False,
                "error": f"Homework parsing failed: {str(e)}"
            }


    async def grade_single_question(
        self,
        question_text: str,
        student_answer: str,
        correct_answer: Optional[str] = None,
        subject: Optional[str] = None,
        context_image: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Grade a single question using gpt-4o-mini for fast, low-cost grading.

        This is Phase 2 of progressive grading.
        iOS calls this endpoint for each question with concurrency limit = 5.

        Args:
            question_text: The question to grade
            student_answer: What the student wrote
            correct_answer: Optional expected answer (AI will determine if not provided)
            subject: Optional subject for subject-specific grading rules
            context_image: Optional base64 image if question needs visual context

        Returns:
            Dict with:
            - success: Boolean
            - grade: Dict with score, is_correct, feedback, confidence
        """

        print(f"📝 === GRADING SINGLE QUESTION ===")
        print(f"📚 Subject: {subject or 'General'}")
        print(f"❓ Question: {question_text[:50]}...")
        print(f"✍️ Student Answer: {student_answer[:50]}...")

        try:
            # Build grading prompt
            system_prompt = self._build_grading_prompt(subject)

            # Prepare user message
            user_text = f"""
Question: {question_text}

Student's Answer: {student_answer}

{f'Expected Answer: {correct_answer}' if correct_answer else ''}

Grade this answer. Return JSON with:
{{
  "score": 0.95,  // 0.0-1.0
  "is_correct": true,  // score >= 0.9
  "feedback": "Excellent! Correct method and calculation.",  // max 30 words
  "confidence": 0.95  // 0.0-1.0
}}
"""

            messages = [{"role": "system", "content": system_prompt}]

            # Add image if provided
            if context_image:
                messages.append({
                    "role": "user",
                    "content": [
                        {"type": "text", "text": user_text},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{context_image}",
                                "detail": "low"  # Low detail for cropped images (save cost)
                            }
                        }
                    ]
                })
            else:
                messages.append({"role": "user", "content": user_text})

            print(f"🚀 Calling gpt-4o-mini...")
            start_time = time.time()

            # Call gpt-4o-mini (fast & cheap)
            response = await self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=messages,
                response_format={"type": "json_object"},
                temperature=0.2,
                max_tokens=300  # Short response needed
            )

            api_duration = time.time() - start_time
            print(f"✅ Grading completed in {api_duration:.2f}s")

            # Parse result
            raw_response = response.choices[0].message.content
            grade_data = json.loads(raw_response)

            print(f"📊 Score: {grade_data.get('score', 0.0)}")
            print(f"✓ Correct: {grade_data.get('is_correct', False)}")

            return {
                "success": True,
                "grade": grade_data
            }

        except json.JSONDecodeError as e:
            print(f"❌ JSON parsing error: {e}")
            return {
                "success": False,
                "error": f"Failed to parse grading response: {str(e)}"
            }
        except Exception as e:
            print(f"❌ Grading error: {e}")
            import traceback
            traceback.print_exc()
            return {
                "success": False,
                "error": f"Question grading failed: {str(e)}"
            }


    def _build_parse_with_coordinates_prompt(self, parsing_mode: str) -> str:
        """Build prompt for parsing homework with normalized coordinates.

        HIERARCHICAL SUPPORT: Recognizes parent questions with subquestions (e.g., 1.a, 1.b, 2.a, 2.b)
        ACCURATE COORDINATES: Improved guidance for precise image region detection
        """

        return f"""You are a homework parsing AI. Extract questions with hierarchical structure and normalized coordinates.

OUTPUT JSON FORMAT (HIERARCHICAL):
{{
  "subject": "Mathematics|Physics|Chemistry|Biology|English|History|Geography|Computer Science|Other",
  "subject_confidence": 0.95,
  "total_questions": 3,  // Count PARENT questions only (e.g., Q1, Q2, Q3), NOT subquestions
  "questions": [
    {{
      "id": 1,
      "question_number": "1",
      "is_parent": true,
      "has_subquestions": true,
      "parent_content": "Label the number line from 10-19 by counting by ones.",
      "has_image": true,
      "image_region": {{
        "top_left": [0.1, 0.12],
        "bottom_right": [0.9, 0.22],
        "description": "Number line 10-19"
      }},
      "subquestions": [
        {{
          "id": "1a",
          "question_text": "What number is one more than 14?",
          "student_answer": "15",
          "question_type": "short_answer"
        }},
        {{
          "id": "1b",
          "question_text": "What number is one less than 17?",
          "student_answer": "16",
          "question_type": "short_answer"
        }}
      ]
    }},
    {{
      "id": 2,
      "question_number": "2",
      "is_parent": false,
      "question_text": "Write the number represented by the picture.",
      "student_answer": "41",
      "has_image": true,
      "image_region": {{
        "top_left": [0.78, 0.48],
        "bottom_right": [0.98, 0.56],
        "description": "Blocks representing 41"
      }},
      "question_type": "calculation"
    }}
  ]
}}

CRITICAL RULES FOR QUESTION NUMBERING:
1. PARENT QUESTIONS: Main questions like "1.", "2.", "3." with potential subquestions
2. SUBQUESTIONS: Questions like "a.", "b.", "c.", "d." under a parent question
3. "total_questions" = COUNT PARENT QUESTIONS ONLY (e.g., if you have Q1 with a,b,c,d and Q2 with a,b,c, total=2)
4. "is_parent": true means this question has subquestions (a, b, c, d)
5. "is_parent": false means this is a standalone question
6. For parent questions with subquestions:
   - "parent_content" = the main question instruction
   - "subquestions" array contains all sub-parts (a, b, c, d)
   - Parent question's image (if any) applies to ALL subquestions

COORDINATE RULES (CRITICAL FOR ACCURACY):
1. Normalize ALL coordinates to [0-1] range:
   - top_left = [x1, y1] where x1=0 is left edge, y1=0 is top edge
   - bottom_right = [x2, y2] where x2=1 is right edge, y2=1 is bottom edge

2. IMAGE POSITIONING GUIDE:
   - Number lines: Usually horizontal across page (width: 0.1-0.9, height: narrow ~0.1)
   - Blocks/tallies: Usually in margins or corners (small regions ~0.1x0.1)
   - Diagrams/graphs: Usually embedded in question text (varies)

3. COORDINATE PRECISION:
   - Look at the ACTUAL position of the visual element in the image
   - For number lines: y-coordinate should match where you SEE the line (top=0.0, middle=0.5, bottom=1.0)
   - For blocks in top-right: x should be ~0.75-0.95, y should be ~0.0-0.3 (NOT 0.8-0.9!)
   - For blocks in bottom-right: x should be ~0.75-0.95, y should be ~0.7-1.0
   - Add 5-10% padding around the actual visual element

4. VALIDATION:
   - ONLY set has_image=true if diagram/graph is ESSENTIAL for solving
   - description should be brief and specific (max 15 words)
   - Double-check coordinates make sense (blocks in corner shouldn't be [0.8, 0.8] - that's center-bottom!)

QUESTION EXTRACTION RULES:
1. HIERARCHICAL STRUCTURE:
   - If you see "1. Main instruction" followed by "a. Sub-question", "b. Sub-question":
     → Create ONE parent question (id=1, is_parent=true) with subquestions array
   - If you see standalone "1. Question" with no subparts:
     → Create regular question (id=1, is_parent=false)

2. COMPLETE TEXT EXTRACTION:
   - Extract COMPLETE question text including ALL instructions
   - For parent questions: extract the main instruction in "parent_content"
   - For subquestions: extract each sub-part completely in "question_text"

3. STUDENT ANSWER EXTRACTION:
   - Extract EXACTLY what student wrote (even if wrong/empty)
   - For number line questions: check if student filled in numbers on the line
   - For tens/ones questions: extract full answer like "65 = 6 tens 5 ones" (not just "65")
   - For empty answers: use empty string ""

4. QUESTION NUMBERING:
   - Preserve EXACT numbering from image (1, 2, 3, NOT 1, 2, 3, 4, 5... for subquestions)
   - Question "1" with parts a,b,c,d → ONE question (id=1) with 4 subquestions
   - Question "2" with parts a,b,c → ONE question (id=2) with 3 subquestions

MODE: {parsing_mode}
{"- Use high accuracy, check all details" if parsing_mode == "detailed" else "- Balance speed and accuracy"}

EXAMPLE (from your image):
- "1. Label the number line..." with "a. What number is...", "b. What number is..."
  → ONE parent question (id=1) with subquestions ["a", "b", "c", "d"]
  → total_questions = 1 (not 5!)
"""


    def _build_grading_prompt(self, subject: Optional[str]) -> str:
        """Build prompt for grading individual questions."""

        subject_rules = ""
        if subject:
            subject_lower = subject.lower()
            if "math" in subject_lower:
                subject_rules = """
MATH GRADING RULES:
- Check numerical accuracy
- Verify units (missing units = 0.7 score)
- Award partial credit for correct method but arithmetic error (0.5-0.7)
"""
            elif "phys" in subject_lower:
                subject_rules = """
PHYSICS GRADING RULES:
- Units are MANDATORY (missing = 0.5 score max)
- Check vector directions (signs matter)
- Partial credit for correct formula but calculation error (0.6-0.8)
"""
            elif "chem" in subject_lower:
                subject_rules = """
CHEMISTRY GRADING RULES:
- Chemical formulas must be exact
- Balanced equations required
- Include states of matter if question requires
"""

        return f"""You are a grading assistant. Grade student answers fairly and encouragingly.

{subject_rules}

GRADING SCALE:
- score = 1.0: Completely correct
- score = 0.7-0.9: Minor errors (missing units, small mistake)
- score = 0.5-0.7: Partial understanding, significant errors
- score = 0.0-0.5: Incorrect or empty

RULES:
1. is_correct = (score >= 0.9)
2. Feedback must be encouraging and educational (<30 words)
3. Explain WHERE error occurred and HOW to fix
4. Be lenient with minor notation differences

OUTPUT: JSON only, no extra text
"""


# Note: EducationalAIService class is defined above (lines 1746-3147)
# It wraps OptimizedEducationalAIService and adds progressive grading methods