# Email Service Setup Guide

The backend is now configured to send verification codes via email. Choose one of the options below:

---

## Option 1: Gmail (Easiest for Testing) ✅ RECOMMENDED

### Step 1: Create an App Password

1. Go to your Google Account: https://myaccount.google.com/
2. Click "Security" in the left menu
3. Enable "2-Step Verification" if not already enabled
4. Click "App passwords" (under 2-Step Verification)
5. Select "Mail" and "Other (Custom name)" → Type "StudyAI"
6. Click "Generate" → Copy the 16-character password

### Step 2: Add to Railway Environment Variables

In your Railway project → Variables tab, add:

```
EMAIL_SERVICE=gmail
EMAIL_USER=your-email@gmail.com
EMAIL_PASSWORD=your-16-char-app-password
EMAIL_FROM=StudyAI <your-email@gmail.com>
```

### Step 3: Redeploy

Click "Deploy" in Railway or push your code.

✅ **Done!** Emails will be sent from your Gmail account.

---

## Option 2: Outlook/Hotmail

### Environment Variables:

```
EMAIL_SERVICE=outlook
EMAIL_USER=your-email@outlook.com
EMAIL_PASSWORD=your-password
EMAIL_FROM=StudyAI <your-email@outlook.com>
```

**Note:** You may need to enable "Allow less secure apps" in Outlook settings.

---

## Option 3: Custom SMTP (Any Email Provider)

For services like SendGrid, Mailgun, AWS SES, etc.

### Environment Variables:

```
EMAIL_SERVICE=smtp
EMAIL_USER=your-smtp-username
EMAIL_PASSWORD=your-smtp-password
EMAIL_FROM=noreply@yourdomain.com
SMTP_HOST=smtp.yourprovider.com
SMTP_PORT=587
SMTP_SECURE=false
```

### Example: SendGrid SMTP

```
EMAIL_SERVICE=smtp
EMAIL_USER=apikey
EMAIL_PASSWORD=your-sendgrid-api-key
EMAIL_FROM=noreply@yourdomain.com
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_SECURE=false
```

---

## Testing Email Configuration

### Option 1: Test on Railway

1. Set environment variables in Railway
2. Redeploy your app
3. Try registering with your iOS app
4. Check if email arrives

### Option 2: Test Locally

```bash
cd /Users/bojiang/StudyAI_Workspace_GitHub/01_core_backend

# Set environment variables
export DATABASE_URL="your-railway-database-url"
export EMAIL_SERVICE=gmail
export EMAIL_USER=your-email@gmail.com
export EMAIL_PASSWORD=your-app-password

# Start server
npm start

# In another terminal, test the endpoint
curl -X POST http://localhost:3001/api/auth/send-verification-code \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","name":"Test User"}'
```

---

## Development Mode (No Email Configuration)

If you **don't configure email variables**, the system will:
- ✅ Still work (won't crash)
- ✅ Log verification codes to Railway logs
- ⚠️ Not send actual emails

This is useful for:
- Development/testing
- Demo purposes
- Before you're ready to configure email

---

## Email Template Preview

Users will receive a beautiful HTML email:

```
┌─────────────────────────────────┐
│   Welcome to StudyAI!           │
│                                 │
│   Hi [Name],                    │
│                                 │
│   Your verification code is:    │
│                                 │
│        123456                   │
│                                 │
│   Expires in 10 minutes         │
│                                 │
│   Best regards,                 │
│   The StudyAI Team              │
└─────────────────────────────────┘
```

---

## Troubleshooting

### Gmail: "Less secure app blocked"
- Use App Password instead of regular password
- Enable 2-Step Verification first

### Emails going to spam
- Add SPF/DKIM records to your domain
- Or use a dedicated email service (SendGrid, AWS SES)

### "Authentication failed"
- Double-check EMAIL_USER and EMAIL_PASSWORD
- Make sure App Password has no spaces

### Emails not arriving
- Check Railway logs for errors
- Verify EMAIL_FROM is a valid email
- Test with a different email provider

---

## Production Recommendations

For production (high volume), consider:

1. **SendGrid** - 100 free emails/day, easy setup
2. **AWS SES** - $0.10 per 1000 emails
3. **Mailgun** - 5000 free emails/month
4. **Postmark** - Best deliverability

These services have better:
- ✅ Deliverability (less spam)
- ✅ Analytics and tracking
- ✅ Reliability and speed
- ✅ Higher sending limits

---

## Quick Start (TL;DR)

**For Testing:**
1. Go to Railway → Variables
2. Add:
   ```
   EMAIL_SERVICE=gmail
   EMAIL_USER=your-gmail@gmail.com
   EMAIL_PASSWORD=your-gmail-app-password
   ```
3. Redeploy
4. ✅ Emails will work!

**For Production:**
- Use SendGrid, AWS SES, or Mailgun
- Follow "Option 3: Custom SMTP" above
