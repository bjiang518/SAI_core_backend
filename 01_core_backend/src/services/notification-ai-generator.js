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
//
// Used when the OpenAI call fails (timeout, rate-limit, parse error, missing
// API key). Must respect the user's `language_preference` — sending an
// English push to a Chinese user is the same as not sending one. All 7
// languages supported by the iOS client are covered; unknown / unsupported
// codes fall back to English.

const FALLBACK_I18N = {
    en: {
        nearBreakthrough: (v) => ({
            title: `${v.topic}: ${v.pct}% — almost there`,
            body:  `${v.needed} more ${v.needed === 1 ? 'question' : 'questions'} to master ${v.subject}.`,
        }),
        videoNotPracticed: (v) => ({
            title: `You watched — now practice it`,
            body:  `${v.subject} video saved but never applied. Close the gap.`,
        }),
        recentMastery: (v) => ({
            title: `✓ ${v.topic} mastered`,
            body:  `What's next in ${v.subject}?`,
        }),
        goalProgress: (v) => ({
            title: `Goal: ${v.rem} ${v.rem === 1 ? 'question' : 'questions'} away`,
            body:  `${v.pct}% there — finish it tonight.`,
        }),
        accuracyTrend: (v) => ({
            title: `${v.subject} accuracy ${v.dir} today`,
            body:  `${v.today}% vs ${v.yesterday}% yesterday.`,
        }),
        neglectedSubject: (v) => ({
            title: `${v.subject} — ${v.daysAgo} days quiet`,
            body:  `It's been a while. A short session keeps the progress alive.`,
        }),
        streakWarn: (v) => ({
            title: `${v.streak}-day streak on the line`,
            body:  `Don't let it end today.`,
        }),
        streakDefault: () => ({
            title: `Study session ready`,
            body:  `Your practice questions are waiting.`,
        }),
    },
    'zh-Hans': {
        nearBreakthrough: (v) => ({
            title: `${v.topic}：${v.pct}% — 即将突破`,
            body:  `再做 ${v.needed} 题就掌握 ${v.subject}。`,
        }),
        videoNotPracticed: (v) => ({
            title: `看完视频，趁热练一练`,
            body:  `${v.subject} 视频看了但没练。把这段知识收住。`,
        }),
        recentMastery: (v) => ({
            title: `✓ ${v.topic} 已掌握`,
            body:  `${v.subject} 下一关，开始？`,
        }),
        goalProgress: (v) => ({
            title: `目标差 ${v.rem} 题`,
            body:  `已完成 ${v.pct}% — 今晚搞定它。`,
        }),
        accuracyTrend: (v) => ({
            title: `${v.subject} 正确率 ${v.dir}`,
            body:  `今天 ${v.today}%，昨天 ${v.yesterday}%。`,
        }),
        neglectedSubject: (v) => ({
            title: `${v.subject} — ${v.daysAgo} 天没碰`,
            body:  `挺久了，做几道题让进度不掉。`,
        }),
        streakWarn: (v) => ({
            title: `连续 ${v.streak} 天在线，别让它断`,
            body:  `今天 5 分钟就能续上。`,
        }),
        streakDefault: () => ({
            title: `今天的练习题已准备好`,
            body:  `打开看看？三道题就行。`,
        }),
    },
    'zh-Hant': {
        nearBreakthrough: (v) => ({
            title: `${v.topic}：${v.pct}% — 即將突破`,
            body:  `再做 ${v.needed} 題就掌握 ${v.subject}。`,
        }),
        videoNotPracticed: (v) => ({
            title: `看完影片，趁熱練一練`,
            body:  `${v.subject} 影片看了但沒練。把這段知識收住。`,
        }),
        recentMastery: (v) => ({
            title: `✓ ${v.topic} 已掌握`,
            body:  `${v.subject} 下一關，開始？`,
        }),
        goalProgress: (v) => ({
            title: `目標差 ${v.rem} 題`,
            body:  `已完成 ${v.pct}% — 今晚搞定它。`,
        }),
        accuracyTrend: (v) => ({
            title: `${v.subject} 正確率 ${v.dir}`,
            body:  `今天 ${v.today}%，昨天 ${v.yesterday}%。`,
        }),
        neglectedSubject: (v) => ({
            title: `${v.subject} — ${v.daysAgo} 天沒碰`,
            body:  `挺久了，做幾道題讓進度不掉。`,
        }),
        streakWarn: (v) => ({
            title: `連續 ${v.streak} 天在線，別讓它斷`,
            body:  `今天 5 分鐘就能續上。`,
        }),
        streakDefault: () => ({
            title: `今天的練習題已準備好`,
            body:  `打開看看？三道題就行。`,
        }),
    },
    ja: {
        nearBreakthrough: (v) => ({
            title: `${v.topic}：${v.pct}% — もう一息`,
            body:  `あと ${v.needed} 問で ${v.subject} マスター。`,
        }),
        videoNotPracticed: (v) => ({
            title: `見たから、今練習しよう`,
            body:  `${v.subject} 動画は見たけど未練習。ギャップを埋めよう。`,
        }),
        recentMastery: (v) => ({
            title: `✓ ${v.topic} マスター済み`,
            body:  `${v.subject} の次は？`,
        }),
        goalProgress: (v) => ({
            title: `目標まで ${v.rem} 問`,
            body:  `${v.pct}% 達成 — 今夜片付けよう。`,
        }),
        accuracyTrend: (v) => ({
            title: `${v.subject} の正答率 ${v.dir}`,
            body:  `今日 ${v.today}% / 昨日 ${v.yesterday}%。`,
        }),
        neglectedSubject: (v) => ({
            title: `${v.subject} — ${v.daysAgo} 日ご無沙汰`,
            body:  `しばらく振り。短い練習で勘を取り戻そう。`,
        }),
        streakWarn: (v) => ({
            title: `${v.streak} 日連続が途切れそう`,
            body:  `今日で終わらせないで。`,
        }),
        streakDefault: () => ({
            title: `今日の練習問題、準備完了`,
            body:  `3 問だけサクッとどうぞ。`,
        }),
    },
    de: {
        nearBreakthrough: (v) => ({
            title: `${v.topic}: ${v.pct}% — fast geschafft`,
            body:  `${v.needed} ${v.needed === 1 ? 'Aufgabe' : 'Aufgaben'} bis du ${v.subject} meisterst.`,
        }),
        videoNotPracticed: (v) => ({
            title: `Du hast es gesehen — jetzt üben`,
            body:  `${v.subject}-Video gespeichert, nie angewendet. Schließe die Lücke.`,
        }),
        recentMastery: (v) => ({
            title: `✓ ${v.topic} gemeistert`,
            body:  `Was kommt als Nächstes in ${v.subject}?`,
        }),
        goalProgress: (v) => ({
            title: `Ziel: noch ${v.rem} ${v.rem === 1 ? 'Aufgabe' : 'Aufgaben'}`,
            body:  `${v.pct}% erreicht — bring es heute zu Ende.`,
        }),
        accuracyTrend: (v) => ({
            title: `${v.subject} Genauigkeit ${v.dir} heute`,
            body:  `${v.today}% vs. ${v.yesterday}% gestern.`,
        }),
        neglectedSubject: (v) => ({
            title: `${v.subject} — ${v.daysAgo} Tage Pause`,
            body:  `Schon eine Weile her. Eine kurze Session hält den Fortschritt am Leben.`,
        }),
        streakWarn: (v) => ({
            title: `${v.streak}-Tage-Strähne in Gefahr`,
            body:  `Lass sie heute nicht enden.`,
        }),
        streakDefault: () => ({
            title: `Lernsession bereit`,
            body:  `Deine Übungsaufgaben warten.`,
        }),
    },
    es: {
        nearBreakthrough: (v) => ({
            title: `${v.topic}: ${v.pct}% — ya casi`,
            body:  `${v.needed} ${v.needed === 1 ? 'pregunta' : 'preguntas'} más para dominar ${v.subject}.`,
        }),
        videoNotPracticed: (v) => ({
            title: `Lo viste — ahora practícalo`,
            body:  `Video de ${v.subject} guardado pero nunca aplicado. Cierra la brecha.`,
        }),
        recentMastery: (v) => ({
            title: `✓ ${v.topic} dominado`,
            body:  `¿Qué sigue en ${v.subject}?`,
        }),
        goalProgress: (v) => ({
            title: `Meta: ${v.rem} ${v.rem === 1 ? 'pregunta' : 'preguntas'} ${v.rem === 1 ? 'restante' : 'restantes'}`,
            body:  `${v.pct}% logrado — termínalo esta noche.`,
        }),
        accuracyTrend: (v) => ({
            title: `Precisión de ${v.subject} ${v.dir} hoy`,
            body:  `${v.today}% vs ${v.yesterday}% ayer.`,
        }),
        neglectedSubject: (v) => ({
            title: `${v.subject} — ${v.daysAgo} días en silencio`,
            body:  `Ha pasado tiempo. Una sesión corta mantiene viva la racha.`,
        }),
        streakWarn: (v) => ({
            title: `Racha de ${v.streak} días en juego`,
            body:  `No la dejes terminar hoy.`,
        }),
        streakDefault: () => ({
            title: `Sesión de estudio lista`,
            body:  `Tus preguntas de práctica están esperando.`,
        }),
    },
    fr: {
        nearBreakthrough: (v) => ({
            title: `${v.topic} : ${v.pct}% — presque là`,
            body:  `${v.needed} ${v.needed === 1 ? 'question' : 'questions'} de plus pour maîtriser ${v.subject}.`,
        }),
        videoNotPracticed: (v) => ({
            title: `Tu l'as regardée — maintenant pratique`,
            body:  `Vidéo ${v.subject} enregistrée mais jamais appliquée. Comble l'écart.`,
        }),
        recentMastery: (v) => ({
            title: `✓ ${v.topic} maîtrisé`,
            body:  `La suite en ${v.subject} ?`,
        }),
        goalProgress: (v) => ({
            title: `Objectif : ${v.rem} ${v.rem === 1 ? 'question' : 'questions'}`,
            body:  `${v.pct}% — termine-le ce soir.`,
        }),
        accuracyTrend: (v) => ({
            title: `Précision ${v.subject} ${v.dir} aujourd'hui`,
            body:  `${v.today}% vs ${v.yesterday}% hier.`,
        }),
        neglectedSubject: (v) => ({
            title: `${v.subject} — ${v.daysAgo} jours de silence`,
            body:  `Ça fait un moment. Une courte session garde le progrès vivant.`,
        }),
        streakWarn: (v) => ({
            title: `Série de ${v.streak} jours en jeu`,
            body:  `Ne la laisse pas finir aujourd'hui.`,
        }),
        streakDefault: () => ({
            title: `Session d'étude prête`,
            body:  `Tes questions de pratique attendent.`,
        }),
    },
};

/// Pick the right entry for a user's stored language code. Handles short
/// codes ("zh" → "zh-Hans") and unknown codes (fall through to English).
function pickFallbackLang(raw) {
    if (!raw) return 'en';
    if (FALLBACK_I18N[raw]) return raw;
    const base = String(raw).split('-')[0].toLowerCase();
    if (base === 'zh') return 'zh-Hans';
    if (FALLBACK_I18N[base]) return base;
    return 'en';
}

function fallback(signals) {
    const { nearBreakthrough, videoNotPracticed, recentMastery,
            todayStats, yesterdayAccuracy, goalProgress,
            neglectedSubject, streak } = signals;

    const lang = pickFallbackLang(signals.profile?.language_preference);
    const t = FALLBACK_I18N[lang] || FALLBACK_I18N.en;

    if (nearBreakthrough) {
        const pct = Math.round(nearBreakthrough.accuracy * 100);
        const { title, body } = t.nearBreakthrough({
            topic: nearBreakthrough.topic_name,
            pct,
            needed: nearBreakthrough.questions_needed,
            subject: nearBreakthrough.subject,
        });
        return { title, body, action: 'weakness', weakness_key: nearBreakthrough.topic_key };
    }
    if (videoNotPracticed) {
        const { title, body } = t.videoNotPracticed({ subject: videoNotPracticed.subject });
        return { title, body, action: 'weakness', weakness_key: null };
    }
    if (recentMastery) {
        const { title, body } = t.recentMastery({
            topic:   recentMastery.topic_name,
            subject: recentMastery.subject,
        });
        return { title, body, action: 'practice' };
    }
    if (goalProgress && goalProgress.pct >= 80) {
        const rem = goalProgress.target_value - goalProgress.current_value;
        const { title, body } = t.goalProgress({ rem, pct: goalProgress.pct });
        return { title, body, action: 'goal' };
    }
    if (todayStats && yesterdayAccuracy !== null) {
        const delta = todayStats.accuracy - yesterdayAccuracy;
        if (Math.abs(delta) >= 10) {
            const dir = delta > 0 ? `↑${delta}%` : `↓${Math.abs(delta)}%`;
            const { title, body } = t.accuracyTrend({
                subject:   todayStats.top_subject,
                dir,
                today:     todayStats.accuracy,
                yesterday: yesterdayAccuracy,
            });
            return { title, body, action: 'practice' };
        }
    }
    if (neglectedSubject) {
        const { title, body } = t.neglectedSubject({
            subject: neglectedSubject.subject,
            daysAgo: neglectedSubject.days_ago,
        });
        return { title, body, action: 'practice' };
    }
    // Last resort: streak
    const streakDays = streak?.streak_count ?? 0;
    const { title, body } = streakDays > 2
        ? t.streakWarn({ streak: streakDays })
        : t.streakDefault();
    return { title, body, action: 'daily' };
}

module.exports = { generateNotification };
