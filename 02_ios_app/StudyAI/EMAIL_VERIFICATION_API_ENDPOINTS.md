# Email Verification API Endpoints

These endpoints need to be registered in your API gateway for the email verification feature.

---

## 1. Send Verification Code

**Endpoint:** `POST /api/auth/send-verification-code`

**Description:** Sends a 6-digit verification code to the user's email address during registration.

**Request Body:**
```json
{
  "email": "user@example.com",
  "name": "John Doe"
}
```

**Success Response (200):**
```json
{
  "success": true,
  "message": "Verification code sent to your email",
  "expiresIn": 600
}
```

**Error Responses:**
- **400 Bad Request:** Invalid email format
- **409 Conflict:** Email already registered and verified
- **429 Too Many Requests:** Too many code requests (rate limiting)
- **500 Internal Server Error:** Failed to send email

**Backend Implementation Notes:**
- Generate 6-digit random code (e.g., "123456")
- Store code in database/cache with 10-minute expiration
- Send email with verification code
- Limit: 5 code requests per email per hour

---

## 2. Verify Email Code

**Endpoint:** `POST /api/auth/verify-email`

**Description:** Verifies the code entered by user and completes registration.

**Request Body:**
```json
{
  "email": "user@example.com",
  "code": "123456",
  "name": "John Doe",
  "password": "securePassword123"
}
```

**Success Response (200):**
```json
{
  "success": true,
  "message": "Email verified successfully",
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "user_123",
    "email": "user@example.com",
    "name": "John Doe",
    "emailVerified": true,
    "createdAt": "2025-01-15T10:30:00Z"
  }
}
```

**Error Responses:**
- **400 Bad Request:** Invalid code format or missing fields
- **401 Unauthorized:** Invalid or expired verification code
- **404 Not Found:** No verification request found for this email
- **409 Conflict:** Email already registered
- **429 Too Many Requests:** Too many verification attempts
- **500 Internal Server Error:** Server error

**Backend Implementation Notes:**
- Verify code matches stored code
- Check code hasn't expired (10-minute window)
- Create user account in database
- Mark email as verified
- Generate JWT authentication token
- Delete verification code from storage
- Limit: 5 verification attempts per code

---

## 3. Resend Verification Code

**Endpoint:** `POST /api/auth/resend-verification-code`

**Description:** Resends verification code if user didn't receive or code expired.

**Request Body:**
```json
{
  "email": "user@example.com"
}
```

**Success Response (200):**
```json
{
  "success": true,
  "message": "Verification code resent",
  "expiresIn": 600
}
```

**Error Responses:**
- **400 Bad Request:** Invalid email format
- **404 Not Found:** No pending verification for this email
- **429 Too Many Requests:** Too many resend requests (must wait 60 seconds between resends)
- **500 Internal Server Error:** Failed to send email

**Backend Implementation Notes:**
- Generate new 6-digit code
- Invalidate previous code
- Send new code via email
- Update expiration time
- Limit: Maximum 3 resends per verification session
- Minimum 60-second cooldown between resends

---

## Security Considerations

1. **Rate Limiting:**
   - Send verification: 5 requests per email per hour
   - Verify code: 5 attempts per code, then invalidate
   - Resend code: 60-second cooldown, max 3 resends

2. **Code Expiration:**
   - Verification codes expire after 10 minutes
   - Expired codes should be deleted automatically

3. **Account Protection:**
   - Don't reveal if email exists in the system (prevent enumeration)
   - Lock account after too many failed verification attempts
   - Log all verification attempts for security monitoring

4. **Email Validation:**
   - Validate email format before sending
   - Check against disposable email domains (optional)
   - Normalize email addresses (lowercase, trim whitespace)

---

## Email Template

**Subject:** Verify your StudyAI email address

**Body:**
```
Hi [Name],

Welcome to StudyAI!

Your verification code is: **[CODE]**

This code will expire in 10 minutes.

If you didn't create an account with StudyAI, please ignore this email.

Best regards,
The StudyAI Team
```

---

## Database Schema Suggestions

**Table: email_verifications**
```sql
CREATE TABLE email_verifications (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) NOT NULL,
  code VARCHAR(6) NOT NULL,
  name VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  attempts INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  expires_at TIMESTAMP NOT NULL,
  UNIQUE(email)
);

CREATE INDEX idx_email_verifications_email ON email_verifications(email);
CREATE INDEX idx_email_verifications_expires ON email_verifications(expires_at);
```

**Cleanup Job:**
- Run every 5 minutes: `DELETE FROM email_verifications WHERE expires_at < NOW()`

---

## Testing Endpoints

Use these curl commands to test:

```bash
# 1. Send verification code
curl -X POST http://your-api-gateway/api/auth/send-verification-code \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","name":"Test User"}'

# 2. Verify email
curl -X POST http://your-api-gateway/api/auth/verify-email \
  -H "Content-Type: application/json" \
  -d '{
    "email":"test@example.com",
    "code":"123456",
    "name":"Test User",
    "password":"testpass123"
  }'

# 3. Resend code
curl -X POST http://your-api-gateway/api/auth/resend-verification-code \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com"}'
```

---

## Error Response Format

All error responses should follow this format:

```json
{
  "success": false,
  "message": "Human-readable error message",
  "errorCode": "SPECIFIC_ERROR_CODE",
  "statusCode": 400
}
```

Example error codes:
- `INVALID_CODE`: Verification code is incorrect
- `CODE_EXPIRED`: Verification code has expired
- `TOO_MANY_ATTEMPTS`: Too many verification attempts
- `EMAIL_ALREADY_EXISTS`: Email is already registered
- `RATE_LIMIT_EXCEEDED`: Too many requests
