# StudyAI Changelog

## [2.0.0] - 2025-09-02 🚀 Major Session Management Release

### 🎉 Added
- **Session-based conversations** - ChatGPT-like experience with memory
- **Intelligent context compression** - AI summarization when approaching token limits
- **SessionChatView** - New chat interface with persistent conversations
- **Message folding system** - Collapse long messages to save screen space
- **Convert to Session feature** - Transform single Q&A into ongoing conversation
- **Image upload in chat** - Camera functionality within session conversations
- **Session management API** - Complete backend for session CRUD operations
- **Redis integration** - Persistent session storage with 24-hour TTL
- **Visual processing feedback** - Loading indicators for all AI operations

### 🔧 Enhanced
- **QuestionView** - Added session conversion option with prominent UI
- **HomeView** - New "Chat Session" option and modern navigation
- **NetworkService** - Session management methods and conversation history
- **AI response formatting** - Better math rendering in chat bubbles
- **Navigation flow** - Proper view dismissal and callback-based transitions

### 🐛 Fixed
- **Build warnings** - Resolved all Xcode compilation warnings
- **Navigation issues** - Proper session navigation after conversion
- **Async operations** - Removed unnecessary await expressions
- **Variable usage** - Fixed unused variable warnings
- **Deprecated APIs** - Updated to iOS 16+ NavigationLink patterns

### 🛠️ Technical
- **Session API endpoints**: `/api/v1/sessions/create`, `/api/v1/sessions/{id}/message`, `/api/v1/sessions/{id}`
- **Token management** - Automatic compression at 3000+ tokens, keeps recent 6 messages
- **Railway deployment** - Production-ready with Redis support
- **Memory architecture** - Efficient conversation storage and retrieval
- **UI components** - Reusable MessageBubbleView with folding capabilities

### 📱 User Experience
- **One-click conversion** - Seamlessly upgrade from Q&A to chat session
- **Professional loading states** - Consistent visual feedback across all operations
- **Conversation management** - Fold/expand controls for message organization
- **Session information** - Detailed session stats accessible via menu
- **Camera integration** - Upload and analyze images directly in chat

---

## [1.0.0] - 2025-09-01 📚 Initial Release

### Added
- **Question & Answer interface** - Single question processing
- **Image upload and OCR** - Extract text from homework images
- **AI-powered responses** - Mathematical problem solving
- **Subject selection** - Multiple academic subjects
- **LaTeX math rendering** - Proper equation display
- **Railway deployment** - Cloud-hosted AI engine

### Features
- Text input for questions
- Camera integration for homework scanning
- AI analysis with step-by-step solutions
- Math formatting with MathJax
- Multiple subject support
- Image cropping and editing

---

## 🔮 Planned Features

### v2.1.0 - User Accounts & Sync
- User authentication
- Cross-device session sync
- Study progress tracking
- Session history search

### v2.2.0 - Advanced Learning
- Voice input for questions
- Handwriting recognition
- Study session analytics
- Collaborative learning sessions

### v2.3.0 - Export & Sharing
- Export conversations to PDF
- Share sessions with teachers
- Study group functionality
- Performance insights

---

**Version Numbering:**
- **Major.Minor.Patch**
- **Major**: Breaking changes or major feature additions
- **Minor**: New features, backward compatible
- **Patch**: Bug fixes and minor improvements