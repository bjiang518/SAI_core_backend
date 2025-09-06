# Communication Patterns

This document outlines the communication flows between the different services in the StudyAI application.

## High-Level Diagram

```mermaid
graph TD
    subgraph User Facing
        A[iOS App]
    end

    subgraph Backend Services
        B[Core Backend (Vercel)]
        C[AI Engine (Railway)]
    end

    subgraph External Services
        D[OpenAI API]
        E[Supabase DB]
    end

    A -->|1. Login / Health Check| B
    A -->|2. Question / Image / Session| C
    B -->|3. Fallback AI Request| D
    C -->|4. Advanced AI Request| D
    B -->|5. Data Storage (Planned)| E
```

## Detailed Flows

### 1. Login and Health Check (iOS App → Core Backend)

- **Trigger**: User logs in or the app performs a health check.
- **Path**: `iOS App` → `Core Backend (Vercel)`
- **Endpoint**: `/api/auth/login` or `/health`
- **Protocol**: HTTPS
- **Payload**: JSON (for login)
- **Notes**: This is a simple, direct request to the Vercel backend. The Vercel backend handles this without involving the AI Engine.

### 2. Question, Image, and Session Handling (iOS App → AI Engine)

- **Trigger**: User submits a question, uploads an image, or starts a new session.
- **Path**: `iOS App` → `AI Engine (Railway)`
- **Endpoints**: `/api/v1/process-question`, `/api/v1/analyze-image`, `/api/v1/sessions/create`, etc.
- **Protocol**: HTTPS
- **Payload**: JSON or multipart/form-data (for images)
- **Notes**: This is the primary workflow for all AI-related tasks. The iOS app communicates directly with the AI Engine, bypassing the Core Backend for these features.

### 3. Fallback AI Request (Core Backend → OpenAI API)

- **Trigger**: The iOS app fails to connect to the AI Engine and falls back to the Core Backend.
- **Path**: `Core Backend (Vercel)` → `OpenAI API`
- **Endpoint**: `https://api.openai.com/v1/chat/completions`
- **Protocol**: HTTPS
- **Payload**: JSON
- **Notes**: This is a legacy workflow that is still in place as a fallback. The Core Backend makes a direct, simple request to OpenAI.

### 4. Advanced AI Request (AI Engine → OpenAI API)

- **Trigger**: The AI Engine receives a request from the iOS app.
- **Path**: `AI Engine (Railway)` → `OpenAI API`
- **Endpoint**: `https://api.openai.com/v1/chat/completions`
- **Protocol**: HTTPS
- **Payload**: JSON
- **Notes**: The AI Engine uses more sophisticated prompts and may make multiple calls to OpenAI to fulfill a single request (e.g., for chain-of-thought reasoning).

### 5. Data Storage (Core Backend → Supabase DB)

- **Trigger**: (Planned) User data needs to be saved or retrieved.
- **Path**: `Core Backend (Vercel)` → `Supabase DB`
- **Protocol**: PostgreSQL connection
- **Payload**: SQL queries
- **Notes**: This is a planned feature that has not yet been implemented. The architecture documents indicate that the Core Backend will be responsible for all database interactions.

## Summary of Key Observations

- The iOS app is the orchestrator, deciding whether to call the AI Engine or the Core Backend.
- The Core Backend is being relegated to a legacy role, primarily handling authentication and acting as a fallback.
- The AI Engine is the heart of the application, handling all complex logic and external communication with OpenAI.
- There is no direct communication between the Core Backend and the AI Engine.

Now that I've mapped out the communication patterns, I'll move on to proposing architectural improvements.