"""
Improved AI Service with Strict JSON Schema and Fallback Parsing

This enhanced version solves the inconsistent parsing issues by:
1. Enforcing strict JSON response format using OpenAI's response_format parameter
2. Providing robust fallback text parsing when JSON fails
3. Handling multiple questions properly (not just focusing on first one)
4. Maintaining backward compatibility with existing iOS app format
"""

import openai
import asyncio
import json
import re
from typing import Dict, List, Optional, Any
from .prompt_service import AdvancedPromptService, Subject
import os
from dotenv import load_dotenv

load_dotenv()


class ImprovedEducationalAIService:
    """
    Enhanced AI service with consistent JSON parsing and robust fallback mechanisms.
    Solves the inconsistent separator problem (** vs ##) by enforcing strict formatting.
    """
    
    def __init__(self):
        self.client = openai.AsyncOpenAI(
            api_key=os.getenv('OPENAI_API_KEY')
        )
        self.prompt_service = AdvancedPromptService()
        self.model = "gpt-4o"  # Use full model for better JSON compliance
    
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
                response_format={"type": "json_object"}  # Force JSON response
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
        """Create a detailed prompt that enforces strict JSON schema."""
        
        context_info = ""
        if student_context:
            context_info = f"Student context: {student_context.get('student_id', 'anonymous')}"
        
        additional_context = ""
        if custom_prompt:
            additional_context = f"Additional context: {custom_prompt}"
        
        return f"""You are an AI homework helper that analyzes images and extracts ALL questions found.

CRITICAL: You MUST return a valid JSON object with exactly this structure:

{{
  "subject": "detected subject (Mathematics, Physics, Chemistry, Biology, English, History, Geography, Computer Science, Foreign Language, Arts, or Other)",
  "subject_confidence": 0.95,
  "total_questions_found": 3,
  "questions": [
    {{
      "question_number": 1,
      "question_text": "complete question text including all parts and sub-questions",
      "answer": "detailed step-by-step solution with clear explanations",
      "confidence": 0.9,
      "has_visuals": true,
      "sub_parts": ["a) first part", "b) second part"]
    }}
  ],
  "processing_notes": "observations about parsing quality or difficulties"
}}

STRICT RULES:
1. Return ONLY valid JSON - no extra text before or after
2. Extract ALL questions found in the image, not just the first one
3. For multi-part questions (a, b, c), include all parts in sub_parts array
4. Set has_visuals to true if question contains diagrams, graphs, or mathematical figures
5. Provide complete step-by-step solutions in the answer field
6. If unsure about subject, use "Other" and set confidence below 0.7
7. Always include at least one question, even if image is unclear

{context_info}
{additional_context}

Remember: Return ONLY the JSON object, no other text."""
    
    def _validate_json_structure(self, json_data: Dict) -> bool:
        """Validate that JSON has required structure."""
        required_fields = ["subject", "questions"]
        
        if not isinstance(json_data, dict):
            return False
        
        for field in required_fields:
            if field not in json_data:
                return False
        
        if not isinstance(json_data.get("questions"), list):
            return False
        
        if len(json_data["questions"]) == 0:
            return False
        
        # Validate first question structure
        first_question = json_data["questions"][0]
        question_fields = ["question_text", "answer"]
        
        for field in question_fields:
            if field not in first_question:
                return False
        
        return True
    
    def _normalize_json_response(self, json_data: Dict) -> Dict:
        """Normalize JSON response to consistent format."""
        
        normalized = {
            "subject": json_data.get("subject", "Other"),
            "subject_confidence": float(json_data.get("subject_confidence", 0.5)),
            "total_questions": json_data.get("total_questions_found", len(json_data.get("questions", []))),
            "questions": [],
            "processing_notes": json_data.get("processing_notes", "Processed successfully")
        }
        
        # Normalize each question
        for i, question in enumerate(json_data.get("questions", [])):
            normalized_question = {
                "question_number": question.get("question_number", i + 1),
                "question_text": question.get("question_text", "Question text not found"),
                "answer": question.get("answer", "Answer not provided"),
                "confidence": float(question.get("confidence", 0.8)),
                "has_visuals": bool(question.get("has_visuals", False)),
                "sub_parts": question.get("sub_parts", question.get("sub_questions", []))
            }
            normalized["questions"].append(normalized_question)
        
        return normalized
    
    def _convert_to_legacy_format(self, normalized_data: Dict) -> str:
        """Convert normalized JSON to legacy ═══QUESTION_SEPARATOR═══ format for iOS compatibility."""
        
        legacy_response = f"SUBJECT: {normalized_data['subject']}\n"
        legacy_response += f"SUBJECT_CONFIDENCE: {normalized_data['subject_confidence']}\n"
        legacy_response += f"TOTAL_QUESTIONS: {normalized_data['total_questions']}\n"
        legacy_response += f"JSON_PARSING: true\n"
        legacy_response += f"PARSING_METHOD: Enhanced AI Backend Parsing with JSON Schema\n\n"
        
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
        self.client = openai.AsyncOpenAI(
            api_key=os.getenv('OPENAI_API_KEY')
        )
        self.prompt_service = AdvancedPromptService()
        self.model = "gpt-4o-mini"
        
        # Add the improved service for homework parsing
        self.improved_service = ImprovedEducationalAIService()
    
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
    
    # Keep all existing methods for backward compatibility
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