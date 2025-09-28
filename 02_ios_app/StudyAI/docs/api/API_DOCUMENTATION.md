# StudyAI API Documentation

## Overview

StudyAI provides a RESTful API for AI-powered homework assistance and document processing. The API is built with FastAPI and deployed on Railway for production use.

**Base URL**: `https://studyai-ai-engine-production.up.railway.app`

## Authentication

Currently, the API does not require authentication for basic endpoints. Future versions may implement user-based authentication.

## Endpoints

### Health Check

#### GET /health

Check the health status of the API service.

**Response:**
```json
{
  "status": "healthy",
  "service": "StudyAI AI Engine",
  "version": "2.0.0",
  "features": [
    "advanced_prompting",
    "educational_optimization", 
    "practice_generation"
  ]
}
```

### Homework Processing

#### POST /api/v1/process-homework-image

Process a homework image using AI-powered parsing to extract questions and provide detailed answers.

**Request Body:**
```json
{
  "base64_image": "string",
  "prompt": "string (optional)",
  "student_id": "string (optional)"
}
```

**Parameters:**
- `base64_image` (required): Base64-encoded image data of the homework document
- `prompt` (optional): Custom prompt to guide the AI analysis
- `student_id` (optional): Student identifier for tracking purposes

**Response:**
```json
{
  "success": true,
  "questions": [
    {
      "question_number": 1,
      "question_text": "What is the value of x in the equation 2x + 5 = 15?",
      "answer_text": "To solve for x: 2x + 5 = 15. Subtract 5 from both sides: 2x = 10. Divide by 2: x = 5.",
      "confidence": 0.95,
      "has_visual_elements": false
    }
  ],
  "processing_time": 2.3,
  "overall_confidence": 0.92,
  "parsing_method": "AI-Powered Parsing",
  "raw_response": "QUESTION_NUMBER: 1\nQUESTION: What is...\n═══QUESTION_SEPARATOR═══"
}
```

**Response Fields:**
- `success`: Boolean indicating if the processing was successful
- `questions`: Array of parsed questions with the following structure:
  - `question_number`: Integer question number (null for unnumbered questions)
  - `question_text`: Complete restatement of the question
  - `answer_text`: Detailed answer with step-by-step solutions
  - `confidence`: Float confidence score (0.0-1.0)
  - `has_visual_elements`: Boolean indicating if question contains diagrams/graphs
- `processing_time`: Float processing time in seconds
- `overall_confidence`: Float average confidence across all questions
- `parsing_method`: String describing the parsing method used
- `raw_response`: String raw AI response for debugging purposes

**Error Response:**
```json
{
  "success": false,
  "error": "Error message",
  "error_code": "PROCESSING_ERROR"
}
```

**HTTP Status Codes:**
- `200 OK`: Successful processing
- `400 Bad Request`: Invalid request format or missing required fields
- `422 Unprocessable Entity`: Invalid base64 image data
- `500 Internal Server Error`: Server processing error

### Legacy Question Answering

#### POST /api/v1/ask

Legacy endpoint for single question answering (maintained for backward compatibility).

**Request Body:**
```json
{
  "question": "string",
  "context": "string (optional)",
  "subject": "string (optional)"
}
```

**Response:**
```json
{
  "success": true,
  "answer": "Detailed answer text",
  "confidence": 0.85,
  "processing_time": 1.2
}
```

## AI Processing Details

### GPT-4o Vision Integration

The homework processing endpoint leverages OpenAI's GPT-4o model with vision capabilities:

- **Model**: `gpt-4o-2024-08-06`
- **Temperature**: `0.1` (for consistent formatting)
- **Max Tokens**: `3000` (for comprehensive responses)
- **Vision Processing**: Analyzes both text and visual elements in homework images

### Prompt Engineering

The system uses sophisticated prompt engineering for reliable question extraction:

```
You are an expert homework assistant. Analyze this homework image and:

1. IDENTIFY each distinct question or problem in the image
2. RESTATE each question clearly and completely  
3. PROVIDE a detailed answer/solution for each question
4. ASSESS your confidence in each answer (0.0-1.0)
5. DETECT if questions contain visual elements (diagrams, graphs, etc.)
6. SEPARATE each question-answer pair with: ═══QUESTION_SEPARATOR═══

FORMAT each question as:
QUESTION_NUMBER: [number if visible, or "unnumbered"]
QUESTION: [complete restatement]
ANSWER: [detailed solution with step-by-step work]
CONFIDENCE: [0.0-1.0 score]
HAS_VISUALS: [true/false]
═══QUESTION_SEPARATOR═══
```

### Response Format Specification

The AI returns structured responses using delimiter-based separation:

```
QUESTION_NUMBER: 1
QUESTION: What is the value of x in the equation 2x + 5 = 15?
ANSWER: To solve for x: 2x + 5 = 15. Subtract 5 from both sides: 2x = 10. Divide by 2: x = 5.
CONFIDENCE: 0.95
HAS_VISUALS: false
═══QUESTION_SEPARATOR═══
QUESTION_NUMBER: 2
QUESTION: Calculate the area of a circle with radius 7 cm.
ANSWER: Area = πr² = π × 7² = π × 49 = 49π ≈ 153.94 cm²
CONFIDENCE: 0.92
HAS_VISUALS: true
═══QUESTION_SEPARATOR═══
```

## Performance Metrics

### Processing Performance
- **Average Response Time**: 2-3 seconds per homework page
- **Question Identification Accuracy**: 95%+ success rate
- **Confidence Scoring**: Reliable 0.0-1.0 assessment
- **Format Consistency**: 99%+ structured response compliance

### Supported Content Types
- **Text Questions**: Mathematical problems, word problems, essay questions
- **Visual Elements**: Diagrams, graphs, charts, geometric figures
- **Mixed Content**: Questions combining text and visual elements
- **Multiple Formats**: Numbered questions, sub-questions, unnumbered items

## Error Handling

The API implements comprehensive error handling:

### Common Error Types
- `INVALID_IMAGE`: Base64 image data is malformed or unreadable
- `PROCESSING_ERROR`: AI service encountered an error during processing
- `TIMEOUT_ERROR`: Processing exceeded maximum time limit
- `RATE_LIMIT_EXCEEDED`: Too many requests in a short time period

### Fallback Mechanisms
- **Graceful Degradation**: Returns partial results if some questions fail to parse
- **Confidence Thresholds**: Flags low-confidence responses for review
- **Format Validation**: Attempts to parse malformed AI responses
- **Retry Logic**: Automatic retries for transient failures

## Usage Examples

### cURL Example

```bash
curl -X POST "https://studyai-ai-engine-production.up.railway.app/api/v1/process-homework-image" \
  -H "Content-Type: application/json" \
  -d '{
    "base64_image": "iVBORw0KGgoAAAANSUhEUgAA...",
    "student_id": "student123"
  }'
```

### Python Example

```python
import requests
import base64

# Read and encode image
with open("homework.jpg", "rb") as image_file:
    base64_image = base64.b64encode(image_file.read()).decode('utf-8')

# Make API request
response = requests.post(
    "https://studyai-ai-engine-production.up.railway.app/api/v1/process-homework-image",
    json={
        "base64_image": base64_image,
        "student_id": "student123"
    }
)

result = response.json()
print(f"Found {len(result['questions'])} questions")
```

### Swift/iOS Example

```swift
func processHomeworkImage(base64Image: String) async -> (success: Bool, response: String?) {
    guard let url = URL(string: "https://studyai-ai-engine-production.up.railway.app/api/v1/process-homework-image") else {
        return (false, nil)
    }
    
    let requestBody = [
        "base64_image": base64Image,
        "student_id": "ios_user"
    ]
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = String(data: data, encoding: .utf8)
        return (true, response)
    } catch {
        return (false, nil)
    }
}
```

## Rate Limits

Current rate limits (subject to change):
- **Per IP**: 100 requests per minute
- **Per Student ID**: 50 requests per minute
- **Image Size**: Maximum 10MB per image
- **Processing Time**: Maximum 30 seconds per request

## Deployment Information

- **Platform**: Railway
- **Environment**: Production
- **Monitoring**: Health checks every 30 seconds
- **Scaling**: Auto-scaling based on CPU and memory usage
- **Logging**: Structured logging with request tracking

## Support

For API support and questions:
- **Documentation**: This API reference
- **Error Codes**: Detailed error messages in responses
- **Monitoring**: Health endpoint for service status
- **Logs**: Server-side logging for debugging

---

**API Version**: 2.0.0  
**Last Updated**: September 2025  
**Built with**: FastAPI + OpenAI GPT-4o Vision