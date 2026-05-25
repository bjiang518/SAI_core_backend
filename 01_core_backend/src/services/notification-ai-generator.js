'use strict';

/**
 * Notification AI Generator
 * Turns raw user signals into a compelling push notification via GPT-4o-mini.
 *
 * The prompt is carefully engineered to produce specific, surprising copy
 * — not generic motivational filler. Falls back to a template if the API fails.
 */

const OpenAI = require('openai');
const logger  = require('../utils/logger');

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// ─── Language map ─────────────────────────────────────────────────────────────

const LANG_NAMES = {
    en: 'English', zh: 'Chinese (Simplified)', 'zh-Hans': 'Chinese (Simplified)',
    'zh-Hant': 'Chinese (Traditional)', ja: 'Japanese', de: 'German',
    es: 'Spanish', fr: 'French', ko: 'Korean', pt: 'Portuguese',
};

// ─── System prompt ────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `\
You write push notifications for StudyAI — a student homework and AI tutor app.
Your goal: one notification that makes the student genuinely want to open the app immediately.

The best notifications feel like a sharp observation from someone paying close attention
to the student's actual work — surprising, specific, impossible to ignore.

NEVER write:
• "Time to study!" / "Don't forget to practice" / "Keep going!" / "You've got this!"
• Generic motivational phrases with no data
• Exclamation marks unless something genuinely exciting happened (mastery, milestone)

EFFECTIVE examples (high open-rate style):
• "3 questions from mastering fractions — stuck at 67% for 4 days"
• "Math ↑19% this week. Science hasn't been touched in 5 days."
• "You watched the fraction division video but never practiced it. Gap: still open."
• "Yesterday: 48% accuracy — your worst session this week. One retry fixes the week."
• "Goal: 2 questions away. You've done harder things in 3 minutes."
• "Recurring mistake: negative signs in algebra. It's showing up in 4 different topics."

Signal priority — pick the SINGLE most interesting/actionable one:
1. near_breakthrough  — student is close to mastering something specific (highest priority)
2. video_not_practiced — watched a video but never applied it (behavior gap, curiosity)
3. recent_mastery     — just mastered something; celebrate + suggest the next step
4. accuracy_trend     — notable change vs yesterday (≥10 pts up or down)
5. goal_gap           — ≤20% remaining on a goal (clear finish line)
6. neglected_subject  — subject untouched for several days
7. top_error          — a specific recurring mistake showing up across topics
8. streak             — fallback only if nothing else is compelling

Output rules:
- TITLE: ≤40 chars. Open with the specific fact, not a greeting.
- BODY: ≤80 chars. One sharp observation + one implicit next action. No padding.
- action: one of ["weakness", "practice", "goal", "daily"]
  • "weakness"  → opens targeted practice for the near-breakthrough/video topic
  • "practice"  → opens general practice library
  • "goal"      → opens daily challenge
  • "daily"     → opens daily challenge (default fallback)
- weakness_key: include ONLY when action = "weakness" AND near_breakthrough or
  video_not_practiced fired. Use the topic_key from the signal data.

Write title and body in: {LANGUAGE}

Respond with ONLY valid JSON — no markdown, no commentary:
{"title":"...","body":"...","action":"...","weakness_key":"...or omit this field"}`;

// ─── Main function ────────────────────────────────────────────────────────────

/**
 * Generate a personalized push notification from collected signals.
 * @param {object} signals  Output of collectSignals()
 * @returns {{ title, body, action, weakness_key? }}
 */
async function generateNotification(signals) {
    const lang     = signals.profile?.language_preference || 'en';
    const langName = LANG_NAMES[lang] || LANG_NAMES[lang.split('-')[0]] || 'English';

    const systemPrompt = SYSTEM_PROMPT.replace('{LANGUAGE}', langName);
    const userContent  = buildSignalSummary(signals);

    try {
        const response = await openai.chat.completions.create({
            model:       'gpt-4o-mini',
            temperature: 0.85,   // slight creativity — avoids repetitive phrasing
            max_tokens:  160,
            messages: [
                { role: 'system', content: systemPrompt },
                { role: 'user',   content: userContent  },
            ],
            response_format: { type: 'json_object' },
        });

        const raw = response.choices[0].message.content;
        const parsed = JSON.parse(raw);

        // Enforce hard length limits
        const title = (parsed.title || '').slice(0, 40).trim();
        const body  = (parsed.body  || '').slice(0, 80).trim();

        if (!title || !body) throw new Error('AI returned empty title or body');

        logger.info(`[NotifAI] Generated for user (action=${parsed.action}): "${title}"`);
        return {
            title,
            body,
            action:       parsed.action       || 'daily',
            weakness_key: parsed.weakness_key || null,
        };

    } catch (err) {
        logger.warn(`[NotifAI] OpenAI failed, using fallback: ${err.message}`);
        return fallback(signals);
    }
}

// ─── Signal summary for the prompt ───────────────────────────────────────────

function buildSignalSummary(signals) {
    const {
        profile, streak, todayStats, yesterdayAccuracy,
        nearBreakthrough, recentMastery, topError,
        goalProgress, neglectedSubject, videoNotPracticed,
    } = signals;

    const name = profile?.first_name || 'Student';

    const summary = {
        student_name: name,
        streak_days:  streak?.streak_count          ?? 0,
        days_inactive: streak?.days_since_last_study ?? 0,
    };

    if (todayStats) {
        summary.today = {
            questions_answered: todayStats.total,
            accuracy_pct:       todayStats.accuracy,
            top_subject:        todayStats.top_subject,
        };
        if (yesterdayAccuracy !== null) {
            summary.today.vs_yesterday_pct = todayStats.accuracy - yesterdayAccuracy;
        }
    }

    if (nearBreakthrough) {
        summary.near_breakthrough = {
            topic:            nearBreakthrough.topic_name,
            subject:          nearBreakthrough.subject,
            current_accuracy: `${Math.round(nearBreakthrough.accuracy * 100)}%`,
            questions_to_master: nearBreakthrough.questions_needed,
            topic_key:        nearBreakthrough.topic_key,
        };
    }

    if (videoNotPracticed) {
        summary.video_not_practiced = {
            subject:     videoNotPracticed.subject,
            video_title: videoNotPracticed.video_title,
        };
    }

    if (recentMastery) {
        summary.just_mastered = {
            topic:   recentMastery.topic_name,
            subject: recentMastery.subject,
        };
    }

    if (topError) {
        summary.recurring_error = {
            type:            topError.error_type,
            times_seen: topError.count,
        };
    }

    if (goalProgress && goalProgress.pct >= 50) {
        summary.goal = {
            type:       goalProgress.goal_type,
            progress:   `${goalProgress.current_value}/${goalProgress.target_value}`,
            percent:    goalProgress.pct,
            remaining:  goalProgress.target_value - goalProgress.current_value,
        };
    }

    if (neglectedSubject) {
        summary.neglected_subject = {
            subject:  neglectedSubject.subject,
            days_ago: neglectedSubject.days_ago,
        };
    }

    return JSON.stringify(summary, null, 2);
}

// ─── Template fallback (no network needed) ───────────────────────────────────

function fallback(signals) {
    const { nearBreakthrough, videoNotPracticed, recentMastery,
            todayStats, yesterdayAccuracy, goalProgress,
            neglectedSubject, streak } = signals;

    if (nearBreakthrough) {
        const pct = Math.round(nearBreakthrough.accuracy * 100);
        return {
            title: `${nearBreakthrough.topic_name}: ${pct}% — almost there`,
            body:  `${nearBreakthrough.questions_needed} more question${nearBreakthrough.questions_needed > 1 ? 's' : ''} to master ${nearBreakthrough.subject}.`,
            action: 'weakness', weakness_key: nearBreakthrough.topic_key,
        };
    }
    if (videoNotPracticed) {
        return {
            title: `You watched — now practice it`,
            body:  `${videoNotPracticed.subject} video saved but never applied. Close the gap.`,
            action: 'weakness', weakness_key: null,
        };
    }
    if (recentMastery) {
        return {
            title: `✓ ${recentMastery.topic_name} mastered`,
            body:  `What's next in ${recentMastery.subject}?`,
            action: 'practice',
        };
    }
    if (goalProgress && goalProgress.pct >= 80) {
        const rem = goalProgress.target_value - goalProgress.current_value;
        return {
            title: `Goal: ${rem} question${rem > 1 ? 's' : ''} away`,
            body:  `${goalProgress.pct}% there — finish it tonight.`,
            action: 'goal',
        };
    }
    if (todayStats && yesterdayAccuracy !== null) {
        const delta = todayStats.accuracy - yesterdayAccuracy;
        if (Math.abs(delta) >= 10) {
            const dir = delta > 0 ? `↑${delta}%` : `↓${Math.abs(delta)}%`;
            return {
                title: `${todayStats.top_subject} accuracy ${dir} today`,
                body:  `${todayStats.accuracy}% vs ${yesterdayAccuracy}% yesterday.`,
                action: 'practice',
            };
        }
    }
    if (neglectedSubject) {
        return {
            title: `${neglectedSubject.subject} — ${neglectedSubject.days_ago} days quiet`,
            body:  `It's been a while. A short session keeps the progress alive.`,
            action: 'practice',
        };
    }
    // Last resort: streak
    const streakDays = streak?.streak_count ?? 0;
    return {
        title: streakDays > 2 ? `${streakDays}-day streak on the line` : `Study session ready`,
        body:  streakDays > 2 ? `Don't let it end today.` : `Your practice questions are waiting.`,
        action: 'daily',
    };
}

module.exports = { generateNotification };
