# StudyAI Complete Architecture & Pipeline Documentation

## 🏗️ Overall Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│                 │    │                 │    │                 │    │                 │
│   📱 iOS App    │────│  🤖 AI Engine   │────│  🧠 OpenAI      │    │  💾 Backend     │
│   (SwiftUI)     │    │   (Python)      │    │   (GPT-4o-mini) │    │  (Node.js)      │
│                 │    │                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
        │                       │                       │                       │
   Camera/OCR              Advanced Prompts         AI Processing          User/Progress
   Math Rendering          Subject Detection       Educational AI          Database
   UI Components           Response Optimization   Content Generation      Authentication
```

## 📸 Complete "Take Picture" Pipeline

### **Step 1: User Interaction (iOS App)**
```
User taps "📷 Take Picture" button
     ↓
CameraView.swift presents UIImagePickerController
     ↓
User takes photo and confirms
     ↓
Image captured and passed to processing
```

### **Step 2: Image Processing (iOS - On Device)**
```
QuestionView.swift receives selected image
     ↓
ImageProcessingService.swift processes image:
  • Uses Apple Vision Framework (VNRecognizeTextRequest)
  • OCR extracts text from mathematical equations
  • Post-processes math symbols (× → *, ÷ → /, etc.)
  • Returns extracted text
     ↓
Extracted text appears in question TextEditor
```

### **Step 3: AI Processing Decision (iOS NetworkService)**
```
User taps "Ask AI" or submits question
     ↓
NetworkService.swift decides routing:
  1. Try AI Engine first (localhost:9003)
  2. Fallback to basic backend if AI Engine unavailable
```

### **Step 4: Advanced AI Processing (AI Engine)**
```
POST /api/v1/process-question → main.py
     ↓
FastAPI receives request with:
  • student_id: "test_student_001"
  • question: "2x + 3 = 7" (from OCR)
  • subject: "mathematics"
  • context: student learning context
  • include_followups: true
     ↓
EducationalAIService.process_educational_question()
```

### **Step 5: Advanced Prompt Engineering (AI Engine)**
```
AdvancedPromptService.create_enhanced_prompt():
  1. Detect subject: "mathematics" → Subject.MATHEMATICS
  2. Load mathematics template with:
     • Mobile-friendly notation rules
     • Step-by-step formatting guidelines
     • LaTeX conversion rules
  3. Generate enhanced system prompt (1000+ characters)
  4. Add educational context and formatting rules
```

### **Step 6: OpenAI API Call (AI Engine → OpenAI)**
```
EducationalAIService calls OpenAI:
  • Model: gpt-4o-mini
  • Messages: [system_prompt, user_question]
  • Temperature: 0.3 (consistent educational content)
  • Max tokens: 1500
     ↓
OpenAI processes with advanced educational prompting
     ↓
Returns step-by-step mathematical solution with LaTeX
```

### **Step 7: Educational Enhancement (AI Engine)**
```
EducationalAIService processes OpenAI response:
  1. Extract reasoning steps from AI response
  2. Identify key concepts ("Equation", "Algebra", etc.)
  3. Generate subject-specific follow-up questions
  4. Create learning recommendations
  5. Package into structured educational response
```

### **Step 8: Response Optimization (AI Engine)**
```
AdvancedPromptService.optimize_response():
  • Clean up mathematical notation spacing
  • Ensure mobile-friendly formatting  
  • Prepare LaTeX expressions for iOS renderer
     ↓
Return structured response to iOS:
{
  "response": {
    "answer": "Step-by-step solution with LaTeX",
    "reasoning_steps": ["Step 1: ...", "Step 2: ..."],
    "key_concepts": ["Equation", "Algebra"],
    "follow_up_questions": ["Can you verify...", ...]
  },
  "learning_analysis": {...},
  "processing_time_ms": 1500,
  "model_details": {...}
}
```

### **Step 9: Math Rendering & Display (iOS App)**
```
NetworkService receives enhanced response
     ↓
QuestionView displays answer using MathFormattedText
     ↓
MathFormattingService.parseTextWithMath():
  • Detects mathematical expressions
  • Converts to LaTeX format for proper display
     ↓
MathEquationView renders equations using:
  • WebKit + MathJax for LaTeX rendering
  • Fallback to Unicode for simple expressions
     ↓
User sees beautifully formatted mathematical solution
```

## 🔄 Complete Data Flow

```
📱 Camera → 👁️ OCR → ✍️ Text → 🤖 AI Engine → 🧠 Advanced Prompting → 
🔮 OpenAI → 📚 Educational Processing → 🎨 Math Rendering → 👀 Display
```

## 🏛️ Architecture Components

### **📱 iOS App (02_ios_app)**
- **Location**: `/Users/bojiang/StudyAI_Workspace/02_ios_app/`
- **Technology**: SwiftUI, Apple Vision Framework
- **Responsibilities**:
  - Camera capture and OCR processing
  - Math equation rendering (WebKit + MathJax)
  - UI/UX and user interaction
  - Network communication with AI Engine

### **🤖 AI Engine (03_ai_engine)**
- **Location**: `/Users/bojiang/StudyAI_Workspace/03_ai_engine/`
- **Technology**: Python, FastAPI, OpenAI SDK
- **Responsibilities**:
  - Advanced subject-specific prompt engineering
  - Educational AI processing and optimization
  - OpenAI API integration with educational enhancements
  - Practice question generation and answer evaluation

### **💾 Backend (01_core_backend)**
- **Location**: `/Users/bojiang/StudyAI_Workspace/01_core_backend/`
- **Technology**: Node.js, Supabase
- **Responsibilities**:
  - User authentication and management
  - Progress tracking and learning analytics
  - Fallback for basic AI processing (when AI Engine unavailable)

## 🎯 Key Processing Locations

### **Prompt Engineering**: 
- **File**: `03_ai_engine/src/services/prompt_service.py`
- **Function**: `AdvancedPromptService.create_enhanced_prompt()`
- **Features**: Subject-specific templates, mobile formatting, educational optimization

### **AI Processing**:
- **File**: `03_ai_engine/src/services/openai_service.py`  
- **Function**: `EducationalAIService.process_educational_question()`
- **Features**: OpenAI integration, response enhancement, educational context

### **Math Rendering**:
- **File**: `02_ios_app/StudyAI/StudyAI/Services/MathRenderer.swift`
- **Function**: `MathFormattingService.formatMathForDisplay()`
- **Features**: LaTeX conversion, WebKit rendering, mobile optimization

## 🚀 Current Status

✅ **Fully Functional Pipeline**:
1. Camera capture with OCR ✅
2. Advanced AI processing with educational optimization ✅  
3. Subject-specific prompt engineering ✅
4. Mathematical LaTeX rendering ✅
5. Educational follow-up questions ✅
6. Fallback system architecture ✅

The complete pipeline now provides **professional-grade educational AI tutoring** with advanced mathematical rendering, far superior to basic chatbot implementations!