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

const DEFAULT_REENGAGEMENT_HTML = `<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 32px 24px; color: #1f2937; line-height: 1.6; font-size: 15px;">

  <p>Hi {{name}},</p>

  <p>I noticed you haven't opened StudyAgent in a little while, and I wanted to reach out personally.</p>

  <p>If you stopped because something didn't work, or it just wasn't useful — I'd genuinely like to know. Just hit reply.</p>

  <p>If you forgot it was there, here's what's been added since you last opened the app:</p>

  <ul style="padding-left: 20px; margin: 16px 0;">
    <li style="margin-bottom: 6px;">Photo a homework page, get step-by-step explanations</li>
    <li style="margin-bottom: 6px;">Practice generated from <em>your</em> past mistakes, not random questions</li>
    <li style="margin-bottom: 6px;">Ask questions inside YouTube lessons</li>
    <li style="margin-bottom: 6px;">A knowledge tree that shows what's mastered and what's next</li>
  </ul>

  <p>To say sorry for losing touch, here's a code for <strong>30 days of Premium</strong>, no strings:</p>

  <p style="font-family: 'SF Mono', Menlo, monospace; font-size: 18px; font-weight: 600; letter-spacing: 1px; color: #111827; margin: 8px 0 24px;">{{code}}</p>

  <p style="margin: 0 0 6px;"><strong>Before you start:</strong> please download or update to the latest version — many of the things above only work on the newest build:</p>
  <p style="margin: 6px 0 24px;">
    <a href="${APP_STORE_URL}" style="color: #2563eb; word-break: break-all;">${APP_STORE_URL}</a>
  </p>

  <p style="margin: 0 0 6px;"><strong>Then to redeem:</strong></p>
  <ol style="padding-left: 20px; margin: 6px 0 24px;">
    <li style="margin-bottom: 4px;">Open StudyAgent on your iPhone and sign in to your account</li>
    <li style="margin-bottom: 4px;">Tap the gear icon (top right) and open <em>Plan &amp; Usage</em></li>
    <li style="margin-bottom: 4px;">Scroll down, tap <em>Have a promo code?</em>, paste <code style="font-family: 'SF Mono', Menlo, monospace;">{{code}}</code>, then tap <em>Apply Code</em></li>
  </ol>

  <p>Got a friend or sibling who'd use this? Forward them this email — the same code works for them too. One redemption per person.</p>

  <p>The code's good through {{code_expires_at}}.</p>

  <p style="margin-top: 28px;">Thanks for giving us a try in the first place.</p>

  <p style="margin: 4px 0 0;">— Bo<br><span style="color: #6b7280; font-size: 13px;">Founder, StudyAgent</span></p>

  <p style="color: #9ca3af; font-size: 12px; margin-top: 36px; padding-top: 16px; border-top: 1px solid #e5e7eb;">
    Don't want emails like this? <a href="{{unsubscribe_url}}" style="color: #9ca3af;">Unsubscribe here</a> and I won't bother you again.
  </p>
</div>`;

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
  DEFAULT_REENGAGEMENT_SUBJECT,
  DEFAULT_REENGAGEMENT_HTML,
  DEFAULT_REENGAGEMENT_TEXT,
  FROM_EMAIL,
  APP_URL,
  BACKEND_URL,
};
