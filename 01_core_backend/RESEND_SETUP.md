# Resend Email Setup Guide ✅ RECOMMENDED FOR RAILWAY

The backend has been updated to use **Resend** - a modern HTTPS-based email API that works perfectly with Railway (no SMTP blocking).

---

## Why Resend?

✅ **Works on Railway** - Uses HTTPS instead of SMTP (no port blocking)
✅ **Fast & Reliable** - Instant delivery with 99.9% uptime
✅ **Simple Setup** - Just one API key, no complex config
✅ **Free Tier** - 100 emails/day (3,000/month) for free
✅ **Custom Domain** - Send from your own domain (study-mates.net)

---

## Quick Setup (3 Steps)

### Step 1: Add Environment Variables to Railway

In your Railway project → Variables tab, add:

```
RESEND_API_KEY=re_U4LyYrRS_5G9toBwL1DcwWM19nPbv14Ua
EMAIL_FROM=StudyAI <noreply@study-mates.net>
```

### Step 2: Redeploy

Click "Deploy" in Railway or push your code to trigger deployment.

### Step 3: Test

```bash
curl -X POST https://your-railway-url.railway.app/api/auth/send-verification-code \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","name":"Test User"}'
```

✅ **Done!** Emails will be sent via Resend.

---

## Resend Dashboard

- **Login**: https://resend.com/login
- **Your API Key**: `re_U4LyYrRS_5G9toBwL1DcwWM19nPbv14Ua`
- **View Sent Emails**: https://resend.com/emails
- **Monitor Delivery**: https://resend.com/logs

---

## Custom Domain Setup (Optional)

To send emails from your `study-mates.net` domain instead of `resend.dev`:

### Step 1: Add Domain in Resend

1. Go to https://resend.com/domains
2. Click "Add Domain"
3. Enter `study-mates.net`
4. Copy the DNS records shown

### Step 2: Add DNS Records to Google Domains

Add these DNS records in Google Domains:

| Type | Name | Value (from Resend) | TTL |
|------|------|---------------------|-----|
| TXT | @ | resend-verification=xxx | 3600 |
| MX | @ | feedback-smtp.resend.com | 3600 |
| TXT | @ | v=spf1 include:_spf.resend.com ~all | 3600 |

### Step 3: Verify Domain

1. Wait 5-10 minutes for DNS propagation
2. Click "Verify" in Resend dashboard
3. ✅ Domain verified!

### Step 4: Update Email From

In Railway → Variables:

```
EMAIL_FROM=StudyAI <noreply@study-mates.net>
```

Or any email like:
- `service@study-mates.net`
- `hello@study-mates.net`
- `support@study-mates.net`

---

## Email Template

Users receive this beautiful HTML email:

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

## Development Mode

If you **don't configure RESEND_API_KEY**, the system will:
- ✅ Still work (won't crash)
- ✅ Log verification codes to Railway logs
- ⚠️ Not send actual emails

This is useful for:
- Development/testing
- Demo purposes
- Before you're ready to configure Resend

---

## Troubleshooting

### Emails not arriving
- Check Railway logs for Resend errors
- Verify API key is correct (no spaces)
- Check Resend dashboard for delivery status
- Make sure EMAIL_FROM domain is verified (if using custom domain)

### "Resend API error: Invalid API key"
- Double-check RESEND_API_KEY in Railway variables
- Make sure there are no spaces before/after the key

### Emails going to spam
- Verify your custom domain (study-mates.net)
- Add SPF/DKIM records as shown above
- Use a verified sender email address

---

## Pricing (After Free Tier)

| Plan | Price | Emails/Month | Best For |
|------|-------|--------------|----------|
| Free | $0 | 3,000 | Testing & small apps |
| Pro | $20/mo | 50,000 | Production apps |
| Business | $85/mo | 250,000 | High volume |

**Current Status**: Free tier (3,000 emails/month) is plenty for now.

---

## Comparison: Resend vs SMTP

| Feature | Resend (HTTPS) | Gmail SMTP |
|---------|----------------|------------|
| Works on Railway | ✅ Yes | ❌ Blocked |
| Setup Complexity | ⭐ Simple | ⭐⭐⭐ Complex |
| Delivery Speed | ⚡ Instant | 🐌 Slow |
| Custom Domain | ✅ Yes | ⚠️ Limited |
| Analytics | ✅ Yes | ❌ No |
| Rate Limits | 100/sec | 500/day |

---

## Support

- **Resend Docs**: https://resend.com/docs
- **API Reference**: https://resend.com/docs/api-reference/emails/send-email
- **Support**: support@resend.com

---

## Summary

**For Railway Deployment:**
1. Add to Railway Variables:
   ```
   RESEND_API_KEY=re_U4LyYrRS_5G9toBwL1DcwWM19nPbv14Ua
   EMAIL_FROM=StudyAI <noreply@study-mates.net>
   ```
2. Redeploy
3. ✅ Emails will work!

**Old SMTP variables (no longer needed):**
- ~~EMAIL_SERVICE~~ (removed)
- ~~EMAIL_USER~~ (removed)
- ~~EMAIL_PASSWORD~~ (removed)
