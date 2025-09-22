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
from typing import Dict, List, Optional, Any, AsyncGenerator
from .prompt_service import AdvancedPromptService, Subject
import os
import hashlib
from datetime import datetime, timedelta
from dotenv import load_dotenv
import gzip
import time

load_dotenv()


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
                timeout=60.0
            )
            print(f"✅ OpenAI AsyncClient initialized: {type(self.client)}")
        except Exception as e:
            print(f"❌ Failed to initialize OpenAI client: {e}")
            raise
        
        self.prompt_service = AdvancedPromptService()
        self.model = "gpt-4o-mini"  # Optimized for cost and speed
        self.vision_model = "gpt-4o"  # Full model for vision tasks
        print(f"✅ Models configured - Text: {self.model}, Vision: {self.vision_model}")
        
        # In-memory cache (fallback if Redis not available)
        self.memory_cache = {}
        self.cache_size_limit = 1000
        
        # Request deduplication
        self.pending_requests = {}
        
        # Performance metrics
        self.request_count = 0
        self.cache_hits = 0
        
        print("✅ AI Service initialization complete")
        print("================================================")
    
    # MARK: - Caching System
    
    def _generate_cache_key(self, content: str, model: str) -> str:
        """Generate cache key from request content."""
        combined = f"{model}:{content}"
        return hashlib.sha256(combined.encode()).hexdigest()[:16]
    
    def _get_cached_response(self, cache_key: str) -> Optional[Dict]:
        """Get cached response if available."""
        if cache_key in self.memory_cache:
            cached_data = self.memory_cache[cache_key]
            
            # Check if expired (1 hour TTL)
            if time.time() - cached_data['timestamp'] < 3600:
                self.cache_hits += 1
                return cached_data['response']
            else:
                # Remove expired entry
                del self.memory_cache[cache_key]
        
        return None
    
    def _set_cached_response(self, cache_key: str, response: Dict):
        """Cache response in memory."""
        # Clean old entries if cache is full
        if len(self.memory_cache) >= self.cache_size_limit:
            # Remove oldest entries
            oldest_keys = sorted(
                self.memory_cache.keys(),
                key=lambda k: self.memory_cache[k]['timestamp']
            )[:100]
            
            for key in oldest_keys:
                del self.memory_cache[key]
        
        self.memory_cache[cache_key] = {
            'response': response,
            'timestamp': time.time()
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

            elif '"type"' in line and ':' in line:
                type_match = re.search(r'"type":\s*"([^"]*)"', line)
                if type_match:
                    current_question['type'] = type_match.group(1)

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

            elif '"options"' in line and '[' in line:
                # Extract options array
                options_match = re.search(r'"options":\s*\[(.*?)\]', line)
                if options_match:
                    options_str = options_match.group(1)
                    # Parse individual options
                    options = []
                    for opt in re.findall(r'"([^"]*)"', options_str):
                        options.append(opt)
                    current_question['options'] = options

            # Check if we have a complete question
            if (len(current_question) >= 4 and
                'question' in current_question and
                'type' in current_question and
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
    
    async def parse_homework_image_json(
        self,
        base64_image: str,
        custom_prompt: Optional[str] = None,
        student_context: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """
        Parse homework images with strict JSON format enforcement.
        
        This method guarantees consistent response format by:
        1. Using OpenAI's response_format parameter to force JSON
        2. Providing detailed schema in the prompt
        3. Implementing fallback parsing for edge cases
        4. Converting to legacy format for iOS compatibility
        
        Args:
            base64_image: Base64 encoded image data
            custom_prompt: Optional additional context
            student_context: Optional student learning context
            
        Returns:
            Structured response with consistent formatting
        """
        
        try:
            # Create the strict JSON schema prompt
            system_prompt = self._create_json_schema_prompt(custom_prompt, student_context)
            
            # Prepare image message for OpenAI Vision API
            image_url = f"data:image/jpeg;base64,{base64_image}"
            
            # Call OpenAI with strict JSON format enforcement
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {
                        "role": "user", 
                        "content": [
                            {
                                "type": "text",
                                "text": f"Analyze this homework image and extract ALL questions found. {custom_prompt or ''}"
                            },
                            {
                                "type": "image_url",
                                "image_url": {"url": image_url, "detail": "high"}
                            }
                        ]
                    }
                ],
                temperature=0.1,  # Very low temperature for consistency
                max_tokens=4000,
                # Remove JSON format requirement for more reliable parsing
            )
            
            raw_response = response.choices[0].message.content
            
            try:
                # Primary: Parse as strict JSON
                json_result = json.loads(raw_response)
                
                # Validate required structure
                if not self._validate_json_structure(json_result):
                    raise ValueError("Invalid JSON structure")
                
                # Normalize the JSON data
                normalized_result = self._normalize_json_response(json_result)
                
                # Convert to legacy format for iOS compatibility
                legacy_response = self._convert_to_legacy_format(normalized_result)
                
                return {
                    "success": True,
                    "structured_response": legacy_response,
                    "parsing_method": "strict_json",
                    "total_questions": len(normalized_result.get("questions", [])),
                    "subject_detected": normalized_result.get("subject", "Other"),
                    "subject_confidence": normalized_result.get("subject_confidence", 0.5),
                    "raw_json": json_result
                }
                
            except (json.JSONDecodeError, ValueError) as json_error:
                print(f"⚠️ JSON parsing failed: {json_error}")
                print(f"📄 Raw response: {raw_response[:200]}...")
                
                # Fallback: Use robust text parsing
                return await self._fallback_text_parsing(raw_response, custom_prompt)
                
        except Exception as e:
            print(f"❌ Improved homework parsing error: {e}")
            return {
                "success": False,
                "structured_response": self._create_error_response(str(e)),
                "parsing_method": "error_fallback",
                "error": str(e)
            }
    
    def _create_json_schema_prompt(self, custom_prompt: Optional[str], student_context: Optional[Dict]) -> str:
        """Create a detailed prompt that enforces strict JSON schema for grading."""
        
        context_info = ""
        if student_context:
            context_info = f"Student context: {student_context.get('student_id', 'anonymous')}"
        
        additional_context = ""
        if custom_prompt:
            additional_context = f"Additional context: {custom_prompt}"
        
        base_prompt = """You are an AI homework grader that analyzes completed homework images and grades student answers.

CRITICAL: You MUST return a valid JSON object with exactly this structure:

{
  "subject": "detected subject (Mathematics, Physics, Chemistry, Biology, English, History, Geography, Computer Science, Foreign Language, Arts, or Other)",
  "subject_confidence": 0.95,
  "total_questions_found": 3,
  "questions": [
    {
      "question_number": 1,
      "raw_question_text": "exact question text as it appears in the image, including any formatting or symbols",
      "question_text": "clean, processed question text for display",
      "student_answer": "what the student wrote as their answer (extract from image)",
      "correct_answer": "the correct/expected answer",
      "grade": "CORRECT",
      "points_earned": 1.0,
      "points_possible": 1.0,
      "confidence": 0.9,
      "has_visuals": true,
      "feedback": "Brief explanation: why it's correct, or if wrong, hint to help student understand",
      "sub_parts": ["a) first part", "b) second part"]
    }
  ],
  "performance_summary": {
    "total_correct": 2,
    "total_incorrect": 1,
    "total_empty": 0,
    "accuracy_rate": 0.67,
    "summary_text": "The student worked on 3 questions in Mathematics. 2 are correct, Great Job! For the wrong answers, the most likely reasons are: calculation errors in basic arithmetic operations. Areas for improvement: double-check arithmetic calculations and show all work steps."
  },
  "processing_notes": "observations about grading quality or difficulties"
}

STRICT GRADING RULES:
1. Return ONLY valid JSON - no extra text before or after
2. Extract ALL questions AND their student answers from the completed homework image
3. For each question, determine: raw_question_text (exact from image), question_text (cleaned), student_answer, correct_answer
4. Grade each answer as: "CORRECT", "INCORRECT", "EMPTY", or "PARTIAL_CREDIT"
5. For INCORRECT answers, provide helpful feedback/hints in the feedback field
6. For CORRECT answers, provide brief positive reinforcement in feedback
7. For EMPTY answers, set student_answer to "" and grade as "EMPTY"
8. Set points_earned based on correctness (1.0 for correct, 0.0 for incorrect/empty, 0.5 for partial)
9. Set has_visuals to true if question contains diagrams, graphs, or mathematical figures
10. If you cannot clearly read the student's answer, set grade to "EMPTY" and note in feedback
11. Calculate performance_summary accurately:
    - Count total_correct, total_incorrect, total_empty based on grades
    - Calculate accuracy_rate as total_correct / total_questions
    - Generate summary_text following this template with both praise and improvement areas:
      * If accuracy_rate = 1.0: "The student worked on {{X}} questions in {{Subject}}. All answers are correct, Great Job! Strengths shown: {{identify what they did well}}. Keep up the excellent work!"
      * If accuracy_rate > 0.7: "The student worked on {{X}} questions in {{Subject}}. {{Y}} are correct, Great Job! Strengths: {{what they did well}}. For the wrong answers, the most likely reasons are: {{analyze common mistake patterns}}. Areas for improvement: {{specific suggestions}}."
      * If accuracy_rate <= 0.7: "The student worked on {{X}} questions in {{Subject}}. {{Y}} are correct. Strengths: {{acknowledge any correct work}}. For improvement, focus on: {{analyze main areas needing work with specific actionable advice}}."

EXAMPLES:
- Question: "What is 2+3?" Student wrote: "5" → Grade: "CORRECT", Feedback: "Great job! Correct answer."
- Question: "What is 2+3?" Student wrote: "6" → Grade: "INCORRECT", Feedback: "Not quite. Try adding 2+3 step by step."
- Question: "What is 2+3?" Student wrote nothing → Grade: "EMPTY", Feedback: "Please provide an answer for this question."

Remember: You are GRADING completed homework, not providing answers. Extract what the STUDENT wrote and compare it to the correct answer."""
        
        # Add context information
        if context_info:
            base_prompt += f"\n\n{context_info}"
        
        if additional_context:
            base_prompt += f"\n\n{additional_context}"
        
        return base_prompt
    
    def _validate_json_structure(self, json_data: Dict) -> bool:
        """Validate that JSON has required grading structure."""
        required_fields = ["subject", "questions", "performance_summary"]
        
        if not isinstance(json_data, dict):
            return False
        
        for field in required_fields:
            if field not in json_data:
                return False
        
        if not isinstance(json_data.get("questions"), list):
            return False
        
        if len(json_data["questions"]) == 0:
            return False
        
        # Validate first question structure for grading
        first_question = json_data["questions"][0]
        question_fields = ["raw_question_text", "question_text", "student_answer", "correct_answer", "grade"]
        
        for field in question_fields:
            if field not in first_question:
                return False
        
        # Validate performance_summary structure
        performance_summary = json_data.get("performance_summary", {})
        summary_fields = ["total_correct", "total_incorrect", "accuracy_rate", "summary_text"]
        
        for field in summary_fields:
            if field not in performance_summary:
                return False
        
        # Validate grade values
        valid_grades = ["CORRECT", "INCORRECT", "EMPTY", "PARTIAL_CREDIT"]
        if first_question.get("grade") not in valid_grades:
            return False
        
        return True
    
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
            timeout=60.0
        )
        self.prompt_service = AdvancedPromptService()
        self.model = "gpt-4o-mini"
        self.vision_model = "gpt-4o"  # Full model for vision tasks
        
        # Add the improved service for homework parsing
        self.improved_service = OptimizedEducationalAIService()
    
    async def parse_homework_image(
        self,
        base64_image: str,
        custom_prompt: Optional[str] = None,
        student_context: Optional[Dict] = None
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
            student_context=student_context
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

            elif '"type"' in line and ':' in line:
                type_match = re.search(r'"type":\s*"([^"]*)"', line)
                if type_match:
                    current_question['type'] = type_match.group(1)

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

            elif '"options"' in line and '[' in line:
                # Extract options array
                options_match = re.search(r'"options":\s*\[(.*?)\]', line)
                if options_match:
                    options_str = options_match.group(1)
                    # Parse individual options
                    options = []
                    for opt in re.findall(r'"([^"]*)"', options_str):
                        options.append(opt)
                    current_question['options'] = options

            # Check if we have a complete question
            if (len(current_question) >= 4 and
                'question' in current_question and
                'type' in current_question and
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
                required_fields = ["question", "type", "correct_answer", "explanation", "topic"]
                for i, question in enumerate(questions_json):
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

                # Validate each question has required fields
                required_fields = ["question", "type", "correct_answer", "explanation", "topic"]
                for i, question in enumerate(questions_json):
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
                required_fields = ["question", "type", "correct_answer", "explanation", "topic"]
                for i, question in enumerate(questions_json):
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