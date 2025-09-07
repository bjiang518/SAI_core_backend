"""
OpenAI Service with Advanced Educational Processing

Handles OpenAI API integration with sophisticated prompt engineering
and educational response optimization.
"""

import openai
import asyncio
from typing import Dict, List, Optional, Any
from .prompt_service import AdvancedPromptService, Subject
import os
from dotenv import load_dotenv

load_dotenv()


class EducationalAIService:
    """
    Advanced AI service specifically designed for educational content processing.
    Uses sophisticated prompt engineering and response optimization.
    """
    
    def __init__(self):
        self.client = openai.AsyncOpenAI(
            api_key=os.getenv('OPENAI_API_KEY')
        )
        self.prompt_service = AdvancedPromptService()
        self.model = "gpt-4o-mini"  # or "gpt-4" for more complex tasks
    
    async def process_educational_question(
        self, 
        question: str, 
        subject: str,
        student_context: Optional[Dict] = None,
        include_followups: bool = True
    ) -> Dict[str, Any]:
        """
        Process an educational question with advanced AI reasoning.
        
        Args:
            question: Student's question
            subject: Academic subject
            student_context: Optional context about the student's learning profile
            include_followups: Whether to generate follow-up questions
            
        Returns:
            Comprehensive response with explanation, steps, and follow-ups
        """
        
        try:
            # Create enhanced prompt using our prompt engineering service
            system_prompt = self.prompt_service.create_enhanced_prompt(
                question=question,
                subject_string=subject,
                context=student_context
            )
            
            # Call OpenAI with optimized prompt
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": question}
                ],
                temperature=0.3,  # Lower temperature for more consistent educational content
                max_tokens=1500,
                presence_penalty=0.1,
                frequency_penalty=0.1
            )
            
            raw_answer = response.choices[0].message.content
            
            # Optimize the response for better formatting
            optimized_answer = self.prompt_service.optimize_response(raw_answer, subject)
            
            # Generate follow-up questions if requested
            follow_ups = []
            if include_followups:
                follow_ups = self.prompt_service.generate_follow_up_questions(question, subject)
            
            # Extract reasoning steps if present
            reasoning_steps = self._extract_reasoning_steps(optimized_answer)
            
            # Identify key concepts covered
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
                "error": str(e),
                "answer": "I apologize, but I encountered an error processing your question. Please try again.",
                "reasoning_steps": [],
                "key_concepts": [],
                "follow_up_questions": []
            }
    
    def _extract_reasoning_steps(self, response: str) -> List[str]:
        """Extract step-by-step reasoning from the AI response."""
        steps = []
        lines = response.split('\n')
        
        for line in lines:
            line = line.strip()
            # Look for numbered steps or step indicators
            if (line.startswith(('Step ', 'step ', '1.', '2.', '3.', '4.', '5.')) or
                'Step' in line and ':' in line):
                steps.append(line)
        
        return steps
    
    def _identify_key_concepts(self, response: str, subject: str) -> List[str]:
        """Identify key educational concepts mentioned in the response."""
        concepts = []
        response_lower = response.lower()
        
        # Subject-specific concept identification
        math_concepts = [
            'equation', 'fraction', 'algebra', 'geometry', 'calculus',
            'derivative', 'integral', 'function', 'variable', 'coefficient',
            'exponent', 'logarithm', 'trigonometry', 'polynomial'
        ]
        
        physics_concepts = [
            'velocity', 'acceleration', 'force', 'energy', 'momentum',
            'gravity', 'friction', 'wave', 'frequency', 'amplitude',
            'electric', 'magnetic', 'thermodynamics', 'quantum'
        ]
        
        chemistry_concepts = [
            'molecule', 'atom', 'bond', 'reaction', 'catalyst',
            'oxidation', 'reduction', 'acid', 'base', 'solution',
            'concentration', 'equilibrium', 'organic', 'inorganic'
        ]
        
        concept_lists = {
            'mathematics': math_concepts,
            'physics': physics_concepts,
            'chemistry': chemistry_concepts
        }
        
        # Get relevant concepts for the subject
        relevant_concepts = concept_lists.get(subject.lower(), [])
        
        for concept in relevant_concepts:
            if concept in response_lower:
                concepts.append(concept.title())
        
        return list(set(concepts))  # Remove duplicates
    
    async def generate_practice_questions(
        self, 
        topic: str, 
        subject: str, 
        difficulty_level: str = "medium",
        num_questions: int = 3
    ) -> Dict[str, Any]:
        """
        Generate practice questions for a specific topic.
        This is perfect for future features like personalized practice.
        """
        
        try:
            system_prompt = f"""You are an expert educational content creator. Generate {num_questions} practice questions for the topic "{topic}" in {subject}.

Requirements:
- Difficulty level: {difficulty_level}
- Questions should build upon each other in complexity
- Include clear, step-by-step solutions
- Use mobile-friendly mathematical notation
- Focus on understanding, not just computation

Format each question as:
Question N: [question text]
Solution: [detailed solution with steps]
Key Concept: [main concept being tested]
"""
            
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": f"Generate practice questions for: {topic}"}
                ],
                temperature=0.5,  # Slightly higher for variety in questions
                max_tokens=2000
            )
            
            content = response.choices[0].message.content
            questions = self._parse_generated_questions(content)
            
            return {
                "success": True,
                "topic": topic,
                "subject": subject,
                "difficulty_level": difficulty_level,
                "questions": questions
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "questions": []
            }
    
    def _parse_generated_questions(self, content: str) -> List[Dict[str, str]]:
        """Parse generated questions into structured format."""
        questions = []
        current_question = {}
        
        lines = content.split('\n')
        for line in lines:
            line = line.strip()
            
            if line.startswith('Question'):
                if current_question:
                    questions.append(current_question)
                current_question = {"question": line}
            elif line.startswith('Solution:'):
                current_question["solution"] = line[9:].strip()
            elif line.startswith('Key Concept:'):
                current_question["key_concept"] = line[12:].strip()
        
        if current_question:
            questions.append(current_question)
        
        return questions
    
    async def evaluate_student_answer(
        self,
        question: str,
        student_answer: str,
        subject: str,
        correct_answer: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Evaluate a student's answer and provide constructive feedback.
        Perfect for future assessment features.
        """
        
        try:
            system_prompt = f"""You are an expert {subject} tutor. Evaluate the student's answer and provide constructive feedback.

Focus on:
1. Correctness of the final answer
2. Quality of the reasoning process
3. Common mistakes or misconceptions
4. Suggestions for improvement
5. Encouragement and positive reinforcement

Be supportive and educational in your feedback."""
            
            user_message = f"""Question: {question}

Student's Answer: {student_answer}

{f"Correct Answer: {correct_answer}" if correct_answer else ""}

Please evaluate this answer and provide helpful feedback."""
            
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_message}
                ],
                temperature=0.3,
                max_tokens=1000
            )
            
            feedback = response.choices[0].message.content
            
            return {
                "success": True,
                "feedback": feedback,
                "subject": subject
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "feedback": "Unable to evaluate answer at this time."
            }
    
    async def analyze_image_content(
        self,
        base64_image: str,
        image_format: str,
        subject: str = "general",
        student_context: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """
        Analyze image content using OpenAI Vision API for educational content extraction.
        
        Args:
            base64_image: Base64 encoded image data
            image_format: Image format (jpeg, png, webp)
            subject: Academic subject context
            student_context: Optional student information
            
        Returns:
            Extracted content with mathematical formatting and analysis
        """
        
        try:
            # Use subject-specific prompting from PromptService
            system_prompt = self.prompt_service.create_image_analysis_prompt(
                subject_string=subject,
                context=student_context
            )

            # Use GPT-4o which has vision capabilities
            response = await self.client.chat.completions.create(
                model="gpt-4o",  # Use GPT-4o for vision capabilities
                messages=[
                    {"role": "system", "content": system_prompt},
                    {
                        "role": "user", 
                        "content": [
                            {
                                "type": "text",
                                "text": f"Please analyze this {subject} image and extract all educational content with proper mathematical formatting."
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/{image_format};base64,{base64_image}"
                                }
                            }
                        ]
                    }
                ],
                temperature=0.1,  # Very low temperature for accuracy
                max_tokens=2000
            )
            
            extracted_content = response.choices[0].message.content
            
            # Analyze mathematical content
            has_math = self._detect_mathematical_content(extracted_content)
            
            # Generate confidence score based on content quality
            confidence = self._calculate_extraction_confidence(extracted_content)
            
            # Generate suggestions for the student
            suggestions = self._generate_image_analysis_suggestions(extracted_content, subject, has_math)
            
            return {
                "success": True,
                "extracted_text": extracted_content,
                "has_math": has_math,
                "confidence": confidence,
                "suggestions": suggestions,
                "processing_method": "openai_vision_gpt4o"
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "extracted_text": "Unable to analyze image content.",
                "has_math": False,
                "confidence": 0.0,
                "suggestions": ["Please try uploading the image again."]
            }
    
    async def process_image_with_question(
        self,
        base64_image: str,
        image_format: str,
        question: str = "",
        subject: str = "general",
        student_context: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """
        Process an image with optional question context for comprehensive educational analysis.
        
        Args:
            base64_image: Base64 encoded image data
            image_format: Image format (jpeg, png, webp)
            question: Optional question context
            subject: Academic subject
            student_context: Optional student information
            
        Returns:
            Comprehensive educational response with extracted content and AI analysis
        """
        
        try:
            # Use subject-specific prompting with question context from PromptService
            if question:
                system_prompt = self.prompt_service.create_question_with_image_prompt(
                    question=question,
                    subject_string=subject,
                    context=student_context
                )
            else:
                system_prompt = self.prompt_service.create_image_analysis_prompt(
                    subject_string=subject,
                    context=student_context
                )

            # Use GPT-4o for vision + reasoning capabilities
            response = await self.client.chat.completions.create(
                model="gpt-4o",  # GPT-4o for vision + advanced reasoning
                messages=[
                    {"role": "system", "content": system_prompt},
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": f"Please analyze this image and provide comprehensive educational assistance. {f'Context: {question}' if question else ''}"
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/{image_format};base64,{base64_image}"
                                }
                            }
                        ]
                    }
                ],
                temperature=0.2,  # Low temperature for educational accuracy
                max_tokens=2500
            )
            
            ai_response = response.choices[0].message.content
            
            # Extract structured information from the response
            extracted_text = self._extract_image_content(ai_response)
            reasoning_steps = self._extract_reasoning_steps(ai_response)
            key_concepts = self._identify_key_concepts(ai_response, subject)
            
            # Generate follow-up questions
            follow_ups = self._generate_image_based_followups(ai_response, subject)
            
            # Generate learning recommendations
            learning_recs = self._generate_learning_recommendations(ai_response, subject)
            
            # Calculate confidence
            confidence = self._calculate_extraction_confidence(ai_response)
            has_math = self._detect_mathematical_content(ai_response)
            
            return {
                "success": True,
                "answer": ai_response,
                "extracted_text": extracted_text,
                "reasoning_steps": reasoning_steps,
                "key_concepts": key_concepts,
                "follow_up_questions": follow_ups,
                "learning_recommendations": learning_recs,
                "next_steps": [
                    "Practice similar problems to reinforce understanding",
                    "Review key concepts identified in the analysis",
                    "Try variations of this problem type"
                ],
                "has_math": has_math,
                "confidence": confidence
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "answer": "Unable to process image with question context.",
                "extracted_text": "",
                "reasoning_steps": [],
                "key_concepts": [],
                "follow_up_questions": [],
                "learning_recommendations": [],
                "next_steps": [],
                "has_math": False,
                "confidence": 0.0
            }
    
    def _detect_mathematical_content(self, content: str) -> bool:
        """Detect if extracted content contains mathematical expressions."""
        math_indicators = [
            '\\(', '\\)', '\\[', '\\]',  # LaTeX delimiters
            'frac{', 'sqrt{', '^{', '_{',  # LaTeX functions
            '=', '+', '-', '×', '÷', '*', '/',  # Math operators
            'π', 'α', 'β', 'γ', 'δ', 'θ',  # Greek letters
            '∫', '∑', '√', '≤', '≥', '≠',  # Math symbols
            'equation', 'formula', 'solve', 'calculate'  # Math keywords
        ]
        
        content_lower = content.lower()
        return any(indicator in content_lower for indicator in math_indicators)
    
    def _calculate_extraction_confidence(self, content: str) -> float:
        """Calculate confidence score for extracted content."""
        if not content or len(content.strip()) < 10:
            return 0.1
        
        # Factors that increase confidence
        confidence = 0.5  # Base confidence
        
        # Length factor
        if len(content) > 100:
            confidence += 0.2
        if len(content) > 500:
            confidence += 0.1
        
        # Mathematical content factor
        if self._detect_mathematical_content(content):
            confidence += 0.2
        
        # Structure factor (proper sentences, formatting)
        sentences = content.count('.') + content.count('!') + content.count('?')
        if sentences > 2:
            confidence += 0.1
        
        return min(confidence, 1.0)
    
    def _generate_image_analysis_suggestions(self, content: str, subject: str, has_math: bool) -> List[str]:
        """Generate helpful suggestions based on image analysis."""
        suggestions = []
        
        if has_math:
            suggestions.extend([
                "Mathematical content detected - verify equation formatting",
                "Consider solving step-by-step if this is a problem",
                "Check for any symbol recognition errors"
            ])
        
        if subject.lower() in ['mathematics', 'physics', 'chemistry']:
            suggestions.append(f"For {subject} problems, show your work clearly")
        
        suggestions.extend([
            "You can edit the extracted text before submitting",
            "Use the 'Ask AI' button for detailed explanations"
        ])
        
        return suggestions
    
    def _extract_image_content(self, ai_response: str) -> str:
        """Extract the main content from comprehensive AI response."""
        # For now, return the full response as the extracted content
        # In the future, this could parse out just the extracted text portion
        return ai_response[:500] + "..." if len(ai_response) > 500 else ai_response
    
    def _generate_image_based_followups(self, response: str, subject: str) -> List[str]:
        """Generate follow-up questions based on image analysis."""
        followups = []
        
        if 'equation' in response.lower() or 'solve' in response.lower():
            followups.append("Would you like me to solve this step-by-step?")
            followups.append("Do you need help understanding any of the mathematical concepts?")
        
        if subject.lower() == 'mathematics':
            followups.append("Would you like to see similar practice problems?")
        
        followups.append("Is there any part of this content you'd like me to explain further?")
        
        return followups
    
    def _generate_learning_recommendations(self, response: str, subject: str) -> List[str]:
        """Generate learning recommendations based on content analysis."""
        recommendations = []
        
        if self._detect_mathematical_content(response):
            recommendations.extend([
                "Practice similar mathematical problems",
                "Review the fundamental concepts involved",
                "Try solving without looking at the solution first"
            ])
        
        recommendations.extend([
            f"Explore related {subject} topics",
            "Take notes on key concepts for future reference",
            "Ask questions about anything unclear"
        ])
        
        return recommendations

    async def parse_homework_image(
        self,
        base64_image: str,
        custom_prompt: Optional[str] = None,
        student_context: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """
        Parse homework images with structured response format for iOS app.
        
        Returns responses in the exact format expected by the iOS device:
        QUESTION_NUMBER: [number]
        QUESTION: [question text]
        ANSWER: [detailed answer]
        CONFIDENCE: [0.0-1.0]
        HAS_VISUALS: [true/false]
        ═══QUESTION_SEPARATOR═══
        
        Args:
            base64_image: Base64 encoded homework image
            custom_prompt: Optional custom prompt (uses default if not provided)
            student_context: Optional student information
            
        Returns:
            Structured response formatted for iOS parsing
        """
        
        try:
            # Create structured homework parsing prompt
            if custom_prompt:
                system_prompt = custom_prompt
            else:
                system_prompt = self._create_homework_parsing_prompt()

            # Use GPT-4o for vision + reasoning capabilities
            response = await self.client.chat.completions.create(
                model="gpt-4o",  # GPT-4o for vision + advanced reasoning
                messages=[
                    {"role": "system", "content": system_prompt},
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": "Please analyze this homework image and provide structured responses for each question found."
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/jpeg;base64,{base64_image}"
                                }
                            }
                        ]
                    }
                ],
                temperature=0.1,  # Very low temperature for consistent formatting
                max_tokens=3000
            )
            
            structured_response = response.choices[0].message.content
            
            # Validate that the response follows the expected format
            if "═══QUESTION_SEPARATOR═══" not in structured_response:
                # If no proper structure, create a fallback response
                structured_response = self._create_fallback_homework_response()
            
            return {
                "success": True,
                "structured_response": structured_response,
                "processing_method": "openai_vision_gpt4o_homework"
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "structured_response": self._create_fallback_homework_response()
            }
    
    def _create_homework_parsing_prompt(self) -> str:
        """Create the structured prompt for homework parsing."""
        return """You are an expert homework assistant. Analyze this homework image and:

1. IDENTIFY each distinct question or problem in the image
2. RESTATE each question clearly and completely
3. PROVIDE a detailed answer/solution for each question
4. SEPARATE each question-answer pair with the delimiter: ═══QUESTION_SEPARATOR═══

FORMAT your response EXACTLY as follows:

QUESTION_NUMBER: [number if visible, or "unnumbered"]
QUESTION: [complete restatement of the question]
ANSWER: [your detailed answer/solution]
CONFIDENCE: [0.0-1.0 confidence score]
HAS_VISUALS: [true/false if question contains diagrams/graphs]
═══QUESTION_SEPARATOR═══

IMPORTANT INSTRUCTIONS:
- If you see numbered questions (1, 2, 3...), use those numbers
- If questions have letters (a, b, c...), treat them as sub-parts of the same question
- For math problems, show step-by-step solutions
- For reading comprehension, provide complete answers
- Be thorough but concise in your answers
- Always include the QUESTION_SEPARATOR between different questions
- Confidence should reflect how certain you are about the question and answer accuracy
- HAS_VISUALS should be true if the question contains diagrams, graphs, charts, or visual elements

Now analyze the homework image:"""
    
    def _create_fallback_homework_response(self) -> str:
        """Create a fallback response when homework parsing fails."""
        return """QUESTION_NUMBER: unnumbered
QUESTION: I was unable to parse the specific questions from this homework image.
ANSWER: Please try taking a clearer photo or manually entering the questions. Make sure the text is clearly visible and the image is well-lit.
CONFIDENCE: 0.1
HAS_VISUALS: false
═══QUESTION_SEPARATOR═══"""