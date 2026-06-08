/**
 * Email service — thin Resend wrapper + template rendering.
 *
 * Centralizes Resend API key handling, dev-mode console fallback, and
 * Mustache-lite template substitution so callers can author HTML/text bodies
 * with {{name}} {{code}} {{redeem_url}} {{code_expires_at}} {{unsubscribe_url}}
 * placeholders.
 */

const jwt = require('jsonwebtoken');

const FROM_EMAIL = process.env.EMAIL_FROM || 'StudyAgent <noreply@study-mates.net>';
// APP_URL: marketing site (study-mates.net). Used for any user-visible URL that
// should land on the consumer site, e.g. {{redeem_url}} placeholder.
const APP_URL = process.env.APP_URL || 'https://study-mates.net';
// BACKEND_URL: where this Fastify API actually serves from. Used for endpoints
// that are routes ON this backend (e.g. /api/email/unsubscribe). Putting these
// behind APP_URL would 404 unless study-mates.net proxies /api/* to Railway.
const BACKEND_URL = process.env.BACKEND_URL || 'https://sai-backend-production.up.railway.app';

// Public URL of the StudyAgent logo, served by the backend's @fastify/static
// plugin from public/assets/. Email clients hotlink it via standard <img src>
// — base64 inlining was rejected by some webmail clients (notably Gmail web),
// which strip data: URIs and render a broken image icon instead.
function getLogoUrl() {
  return `${BACKEND_URL}/assets/studyagent-logo.png`;
}

let _resend = null;
function getResend() {
  if (_resend !== null) return _resend;
  const key = process.env.RESEND_API_KEY;
  if (!key) {
    _resend = false; // sentinel: configured but disabled
    return _resend;
  }
  const { Resend } = require('resend');
  _resend = new Resend(key);
  return _resend;
}

/**
 * Render a Mustache-lite template — replaces {{key}} with vars[key]. Missing
 * keys render as empty string (so a typo'd placeholder doesn't surface to the
 * recipient as literal "{{name}}"). HTML escaping is the caller's responsibility
 * for HTML bodies; for text bodies escaping is irrelevant.
 */
function renderTemplate(template, vars) {
  if (!template) return '';
  return template.replace(/\{\{\s*(\w+)\s*\}\}/g, (_, key) => {
    const value = vars?.[key];
    return value == null ? '' : String(value);
  });
}

function buildUnsubscribeUrl(userId) {
  const secret = (process.env.JWT_SECRET || 'dev-secret') + '_unsubscribe';
  const token = jwt.sign(
    { userId, list: 'reengagement', purpose: 'unsubscribe' },
    secret,
    { expiresIn: '365d' }
  );
  return `${BACKEND_URL}/api/email/unsubscribe?token=${encodeURIComponent(token)}`;
}

function buildRedeemUrl(code) {
  return `${APP_URL}/redeem?code=${encodeURIComponent(code)}`;
}

/**
 * Send a raw email via Resend. Returns { id } from Resend on success.
 * In dev mode (no RESEND_API_KEY), logs to console and returns { id: 'dev-...' }.
 *
 * Throws on Resend API errors so the caller can mark the send row as failed.
 */
async function sendEmail({ to, subject, html, text, logger = console }) {
  if (!to || !subject || (!html && !text)) {
    throw new Error('sendEmail: to, subject, and html/text are required');
  }

  const resend = getResend();
  if (!resend) {
    logger.warn?.(`📧 [dev-mode] would send to=${to} subject="${subject}"`);
    return { id: `dev-${Date.now()}` };
  }

  const { data, error } = await resend.emails.send({
    from: FROM_EMAIL,
    to: [to],
    subject,
    html: html || undefined,
    text: text || undefined,
  });

  if (error) {
    const msg = error.message || JSON.stringify(error);
    throw new Error(`Resend API error: ${msg}`);
  }
  return { id: data?.id };
}

/**
 * Default re-engagement campaign template. Admin can edit subject/body in the
 * dashboard before launching, but this is what they'll start from.
 *
 * Placeholders: {{name}} {{code}} {{code_expires_at}} {{unsubscribe_url}}
 *
 * (We deliberately don't include a redeem URL — sending traffic through a web
 *  page that re-bounces into the App Store / app is fragile across iOS versions
 *  and Mail clients. Asking the user to open the app once they have the code is
 *  the most reliable path, and StudyAgent is iOS-only anyway.)
 */
const APP_STORE_URL = 'https://apps.apple.com/us/app/studyagent/id6754365864';

const DEFAULT_REENGAGEMENT_SUBJECT = 'A note from StudyAgent, {{name}}';

// Layout uses tables (not flex) so Outlook renders correctly. Inline styles
// throughout — Gmail strips <style> blocks. Solid background-color is set
// before background-image so clients that don't support linear-gradient
// (Outlook) fall back to the brand-blue solid.
const DEFAULT_REENGAGEMENT_HTML = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>StudyAgent</title>
</head>
<body style="margin:0; padding:0; background:#f3f4f6;">
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#f3f4f6; padding:32px 16px; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','Helvetica Neue',Arial,sans-serif;">
  <tr>
    <td align="center">
      <!-- Card -->
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="600" style="max-width:600px; width:100%; background:#ffffff; border-radius:18px; overflow:hidden; box-shadow:0 6px 30px rgba(15,23,42,0.06);">

        <!-- Brand header (gradient with solid fallback) -->
        <tr>
          <td style="background-color:#2563eb; background-image:linear-gradient(135deg,#5BAEDC 0%,#2563eb 100%); padding:30px 36px;">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td valign="middle" style="padding-right:18px;">
                  <img src="{{logo_url}}" width="54" height="54" alt="StudyAgent" style="display:block; border-radius:12px; border:0; outline:none;" />
                </td>
                <td valign="middle">
                  <div style="font-size:24px; font-weight:700; color:#ffffff; letter-spacing:-0.3px; line-height:1.1;">StudyAgent</div>
                  <div style="font-size:13px; color:rgba(255,255,255,0.88); margin-top:4px; line-height:1.3;">Personal AI tutor for students</div>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- Body -->
        <tr>
          <td style="padding:34px 36px 8px; color:#1f2937; line-height:1.65; font-size:15px;">
            <p style="margin:0 0 14px;">Hi {{name}},</p>
            <p style="margin:0 0 14px;">I noticed you haven't opened StudyAgent in a little while, and I wanted to reach out personally.</p>
            <p style="margin:0 0 14px;">If you stopped because something didn't work, or it just wasn't useful — I'd genuinely like to know. Just hit reply.</p>
            <p style="margin:0 0 14px;">If you forgot it was there, here's what's been added since you last opened the app:</p>
            <ul style="padding-left:22px; margin:0 0 22px; color:#374151;">
              <li style="margin-bottom:8px;">Photo a homework page, get step-by-step explanations</li>
              <li style="margin-bottom:8px;">Practice generated from <em>your</em> past mistakes, not random questions</li>
              <li style="margin-bottom:8px;">Ask questions inside YouTube lessons</li>
              <li style="margin-bottom:8px;">A knowledge tree that shows what's mastered and what's next</li>
            </ul>
            <p style="margin:0 0 14px;">To say sorry for losing touch, here's a code for <strong style="color:#111827;">30 days of Premium</strong>, no strings:</p>
          </td>
        </tr>

        <!-- Promo code -->
        <tr>
          <td style="padding:0 36px 26px;">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
              <tr>
                <td align="center" style="background:#f0f7ff; border:2px dashed #7EC8E3; border-radius:14px; padding:22px 16px;">
                  <div style="font-family:'SF Mono',Menlo,Consolas,monospace; font-size:26px; font-weight:700; letter-spacing:3px; color:#2563eb;">{{code}}</div>
                  <div style="font-size:12px; color:#6b7280; margin-top:8px;">Valid through {{code_expires_at}}</div>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- Step 1 — App Store CTA -->
        <tr>
          <td style="padding:0 36px 18px; color:#1f2937; line-height:1.6; font-size:15px;">
            <p style="margin:0 0 12px;"><strong style="color:#111827;">Step 1 — Update or download the app</strong><br /><span style="color:#6b7280; font-size:14px;">Many of the things above only work on the newest build.</span></p>
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:6px 0 4px;">
              <tr>
                <td style="background:#2563eb; border-radius:10px;">
                  <a href="${APP_STORE_URL}" style="display:inline-block; padding:13px 24px; color:#ffffff; text-decoration:none; font-weight:600; font-size:14px; border-radius:10px;">Open in App Store →</a>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- Step 2 — redeem -->
        <tr>
          <td style="padding:14px 36px 8px; color:#1f2937; line-height:1.65; font-size:15px;">
            <p style="margin:0 0 10px;"><strong style="color:#111827;">Step 2 — Redeem inside the app</strong></p>
            <ol style="padding-left:22px; margin:0 0 22px; color:#374151;">
              <li style="margin-bottom:6px;">Sign in to your StudyAgent account</li>
              <li style="margin-bottom:6px;">Tap the gear icon (top right) and open <em>Plan &amp; Usage</em></li>
              <li style="margin-bottom:6px;">Scroll down, tap <em>Have a promo code?</em>, paste <code style="background:#f3f4f6; padding:2px 7px; border-radius:5px; font-family:'SF Mono',Menlo,monospace; font-size:13px;">{{code}}</code>, then tap <em>Apply Code</em></li>
            </ol>

            <p style="margin:0 0 14px; color:#374151;">Got a friend or sibling who'd use this? Forward them this email — the same code works for them too. One redemption per person.</p>

            <p style="margin:24px 0 0;">Thanks for giving us a try in the first place.</p>
            <p style="margin:18px 0 0; font-weight:600; color:#111827;">— Bo</p>
            <p style="margin:2px 0 28px; color:#6b7280; font-size:13px;">Founder, StudyAgent</p>
          </td>
        </tr>

        <!-- Footer -->
        <tr>
          <td style="background:#f9fafb; padding:18px 36px; border-top:1px solid #e5e7eb; text-align:center;">
            <div style="font-size:12px; color:#9ca3af; line-height:1.5;">
              Don't want emails like this? <a href="{{unsubscribe_url}}" style="color:#9ca3af; text-decoration:underline;">Unsubscribe</a> and I won't bother you again.
            </div>
          </td>
        </tr>

      </table>
    </td>
  </tr>
</table>
</body>
</html>`;

const DEFAULT_REENGAGEMENT_TEXT = `Hi {{name}},

I noticed you haven't opened StudyAgent in a little while, and I wanted to reach out personally.

If you stopped because something didn't work, or it just wasn't useful — I'd genuinely like to know. Just hit reply.

If you forgot it was there, here's what's been added since you last opened the app:

  - Photo a homework page, get step-by-step explanations
  - Practice generated from your past mistakes, not random questions
  - Ask questions inside YouTube lessons
  - A knowledge tree that shows what's mastered and what's next

To say sorry for losing touch, here's a code for 30 days of Premium, no strings:

  {{code}}

Before you start: please download or update to the latest version — many of the things above only work on the newest build:

  ${APP_STORE_URL}

Then to redeem:
  1. Open StudyAgent on your iPhone and sign in to your account
  2. Tap the gear icon (top right) and open "Plan & Usage"
  3. Scroll down, tap "Have a promo code?", paste {{code}}, then tap "Apply Code"

Got a friend or sibling who'd use this? Forward them this email — the same code works for them too. One redemption per person.

The code's good through {{code_expires_at}}.

Thanks for giving us a try in the first place.

— Bo
Founder, StudyAgent

—
Don't want emails like this? Unsubscribe: {{unsubscribe_url}}
`;

module.exports = {
  sendEmail,
  renderTemplate,
  buildUnsubscribeUrl,
  buildRedeemUrl,
  getLogoUrl,
  DEFAULT_REENGAGEMENT_SUBJECT,
  DEFAULT_REENGAGEMENT_HTML,
  DEFAULT_REENGAGEMENT_TEXT,
  FROM_EMAIL,
  APP_URL,
  BACKEND_URL,
};
