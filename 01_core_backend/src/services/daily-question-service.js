/**
 * Daily Question Service for StudyAI
 * Generates one age-appropriate fun question per grade level per language per 6-hour slot.
 * Runs 4× per day (00:00, 06:00, 12:00, 18:00 UTC).
 * 15 grades × 7 languages × 4 slots = 420 questions/day (gpt-4o-mini, ~$0.04/day total).
 */

const crypto = require('crypto');
const cron = require('node-cron');
const OpenAI = require('openai');
const { db } = require('../utils/railway-database');
const logger = require('../utils/logger');

const GRADE_LABELS = [
    'Preschool (age 4–5)',
    'Kindergarten (age 5–6)',
    'Grade 1 (age 6–7)',
    'Grade 2 (age 7–8)',
    'Grade 3 (age 8–9)',
    'Grade 4 (age 9–10)',
    'Grade 5 (age 10–11)',
    'Grade 6 (age 11–12)',
    'Grade 7 (age 12–13)',
    'Grade 8 (age 13–14)',
    'Grade 9 (age 14–15)',
    'Grade 10 (age 15–16)',
    'Grade 11 (age 16–17)',
    'Grade 12 (age 17–18)',
    'College / University (age 18+)',
];

const SUPPORTED_LANGUAGES = ['en', 'zh-Hans', 'zh-Hant', 'de', 'es', 'fr', 'ja'];

const LANGUAGE_LABELS = {
    'en':      'English',
    'zh-Hans': 'Simplified Chinese (简体中文)',
    'zh-Hant': 'Traditional Chinese (繁體中文)',
    'de':      'German (Deutsch)',
    'es':      'Spanish (Español)',
    'fr':      'French (Français)',
    'ja':      'Japanese (日本語)',
};

/**
 * Parse Accept-Language header → one of SUPPORTED_LANGUAGES.
 * Handles iOS formats like "zh-Hans-CN;q=1, en;q=0.9".
 */
function detectLanguage(acceptLanguageHeader) {
    if (!acceptLanguageHeader) return 'en';
    const h = acceptLanguageHeader.toLowerCase();
    if (h.includes('zh-hant') || h.includes('zh-tw') || h.includes('zh-hk')) return 'zh-Hant';
    if (h.includes('zh-hans') || h.includes('zh-cn') || h.includes('zh-sg')) return 'zh-Hans';
    // bare "zh" → Simplified (most common)
    if (/\bzh\b/.test(h)) return 'zh-Hans';
    if (h.includes('de')) return 'de';
    if (h.includes('es')) return 'es';
    if (h.includes('fr')) return 'fr';
    if (h.includes('ja')) return 'ja';
    return 'en';
}

class DailyQuestionService {
    constructor() {
        this.cronJob = null;
        this.isInitialized = false;
        this.generationInProgress = false;
        this.openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
    }

    async initialize() {
        if (this.isInitialized) {
            logger.debug('⚠️ [DailyQuestion] Already initialized — skipping');
            return;
        }

        try {
            logger.debug('📅 [DailyQuestion] Initializing service...');
            await this._ensureTable();
            await this._ensureSeenTable();
            logger.debug('✅ [DailyQuestion] Table ready');

            this.cronJob = cron.schedule('0 0,6,12,18 * * *', async () => {
                const slot = this._currentSlot();
                logger.debug(`⏰ [DailyQuestion] Cron fired — starting generation for slot ${slot}`);
                await this._generateAll();
            }, { scheduled: true, timezone: 'UTC' });

            logger.debug(`🕕 [DailyQuestion] Cron scheduled at 00:00/06:00/12:00/18:00 UTC (${GRADE_LABELS.length} grades × ${SUPPORTED_LANGUAGES.length} languages × 4 slots = ${GRADE_LABELS.length * SUPPORTED_LANGUAGES.length * 4} questions/day)`);

            logger.debug('🚀 [DailyQuestion] Startup generation check...');
            await this._generateAll();

            this.isInitialized = true;
            logger.debug('✅ [DailyQuestion] Service ready');
        } catch (error) {
            logger.error('❌ [DailyQuestion] Failed to initialize:', error);
        }
    }

    stop() {
        if (this.cronJob) {
            this.cronJob.stop();
            this.cronJob.destroy();
            this.cronJob = null;
        }
        this.isInitialized = false;
        logger.debug('🛑 [DailyQuestion] Service stopped');
    }

    /**
     * Return the current question for a given grade + language (for the current 6-hour slot).
     * Triggers on-demand generation if not yet in DB.
     */
    async getTodayQuestion(gradeLevel, language = 'en') {
        const lang = SUPPORTED_LANGUAGES.includes(language) ? language : 'en';
        const today = this._todayUTC();
        const slot  = this._currentSlot();
        logger.debug(`🔍 [DailyQuestion] getTodayQuestion — grade=${gradeLevel}, lang=${lang}, date=${today}, slot=${slot}`);

        const result = await db.query(
            'SELECT question_text, fun_fact, subject FROM daily_questions WHERE question_date = $1 AND grade_level = $2 AND language = $3 AND time_slot = $4',
            [today, gradeLevel, lang, slot]
        );

        if (result.rows.length > 0) {
            const q = result.rows[0];
            logger.debug(`📦 [DailyQuestion] Cache hit — grade=${gradeLevel}, lang=${lang}, slot=${slot}, subject=${q.subject}`);
            logger.debug(`   question: "${q.question_text}"`);
            return q;
        }

        logger.debug(`📝 [DailyQuestion] Cache miss — generating on-demand for grade=${gradeLevel}, lang=${lang}, slot=${slot}`);
        return await this._generateForGrade(gradeLevel, today, lang, slot);
    }

    async triggerManualGeneration() {
        logger.debug('🔧 [DailyQuestion] Manual generation triggered — force=true');
        await this._generateAll(true);
    }

    getStatus() {
        return {
            isInitialized: this.isInitialized,
            generationInProgress: this.generationInProgress,
            nextGenerationTime: '00:00 / 06:00 / 12:00 / 18:00 UTC',
            currentSlot: this._currentSlot(),
            gradeLevels: GRADE_LABELS.length,
            languages: SUPPORTED_LANGUAGES,
            slotsPerDay: 4,
            totalPerDay: GRADE_LABELS.length * SUPPORTED_LANGUAGES.length * 4,
        };
    }

    // ──────────────────────────────────────────────────────────────────────────

    async _generateAll(force = false) {
        if (this.generationInProgress) {
            logger.debug('⚠️ [DailyQuestion] Generation already in progress — skipping');
            return;
        }
        this.generationInProgress = true;
        const today = this._todayUTC();
        const slot  = this._currentSlot();
        const total = GRADE_LABELS.length * SUPPORTED_LANGUAGES.length;

        logger.debug(`\n${'─'.repeat(60)}`);
        logger.debug(`📚 [DailyQuestion] === GENERATION START ===`);
        logger.debug(`   Date     : ${today}`);
        logger.debug(`   Slot     : ${slot} (${slot * 6}:00–${slot * 6 + 5}:59 UTC)`);
        logger.debug(`   Grades   : ${GRADE_LABELS.length}   Languages: ${SUPPORTED_LANGUAGES.join(', ')}`);
        logger.debug(`   Total    : ${total} questions   Force: ${force}`);
        logger.debug(`${'─'.repeat(60)}`);

        let generated = 0, skipped = 0, failed = 0;
        const startTime = Date.now();

        try {
            for (const lang of SUPPORTED_LANGUAGES) {
                logger.debug(`\n🌐 [DailyQuestion] Language: ${lang} (${LANGUAGE_LABELS[lang]})`);

                for (let grade = 0; grade < GRADE_LABELS.length; grade++) {
                    if (!force) {
                        const exists = await db.query(
                            'SELECT 1 FROM daily_questions WHERE question_date=$1 AND grade_level=$2 AND language=$3 AND time_slot=$4',
                            [today, grade, lang, slot]
                        );
                        if (exists.rows.length > 0) {
                            logger.debug(`   ⏭️  Grade ${String(grade).padStart(2)} — already exists`);
                            skipped++;
                            continue;
                        }
                    }

                    try {
                        const q = await this._generateForGrade(grade, today, lang, slot);
                        logger.debug(`   ✅ Grade ${String(grade).padStart(2)} (${GRADE_LABELS[grade]})`);
                        logger.debug(`         subject : ${q.subject}`);
                        logger.debug(`         question: ${q.question_text}`);
                        logger.debug(`         fun_fact: ${q.fun_fact ?? '(none)'}`);
                        generated++;
                    } catch (err) {
                        logger.error(`   ❌ Grade ${grade}, lang=${lang} — FAILED: ${err.message}`);
                        failed++;
                    }
                }
            }
        } finally {
            this.generationInProgress = false;
            const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
            logger.debug(`\n${'─'.repeat(60)}`);
            logger.debug(`📊 [DailyQuestion] === GENERATION SUMMARY ===`);
            logger.debug(`   Generated : ${generated}   Skipped: ${skipped}   Failed: ${failed}`);
            logger.debug(`   Duration  : ${elapsed}s`);
            logger.debug(`${'─'.repeat(60)}\n`);
        }
    }

    async _generateForGrade(gradeLevel, date, language, slot = 0) {
        const gradeLabel = GRADE_LABELS[gradeLevel] || `Grade ${gradeLevel}`;
        const langLabel  = LANGUAGE_LABELS[language] || language;

        const prompt = `You are generating a fun "Did you know?" question IN ${langLabel} for students in ${gradeLabel}.

The question should:
- Be written entirely in ${langLabel}
- Be genuinely surprising or counterintuitive
- Be age-appropriate and engaging
- Cover any topic: science, history, nature, technology, art, culture, sports
- Be phrased naturally in ${langLabel} (e.g. "你知道吗..." for Chinese, "Wusstest du..." for German)

Respond ONLY with valid JSON (no markdown, no code block):
{
  "question": "<question in ${langLabel}>",
  "fun_fact": "<one sentence explanation in ${langLabel}>",
  "subject": "Science|History|Nature|Technology|Art|Sports|Math|Other"
}`;

        logger.debug(`   🤖 [DailyQuestion] OpenAI call — grade=${gradeLevel}, lang=${language}, slot=${slot}`);

        const response = await this.openai.chat.completions.create({
            model: 'gpt-4o-mini',
            messages: [{ role: 'user', content: prompt }],
            max_tokens: 250,
            temperature: 1.0,
        });

        const raw = response.choices[0].message.content.trim();
        logger.debug(`   📨 [DailyQuestion] Raw response (grade=${gradeLevel}, lang=${language}, slot=${slot}): ${raw}`);

        let parsed;
        try {
            parsed = JSON.parse(raw);
        } catch {
            logger.warn(`   ⚠️ [DailyQuestion] JSON parse failed — using raw text`);
            parsed = { question: raw, fun_fact: null, subject: 'Other' };
        }

        await db.query(
            `INSERT INTO daily_questions (question_date, grade_level, language, time_slot, question_text, fun_fact, subject)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (question_date, time_slot, grade_level, language) DO UPDATE
               SET question_text = EXCLUDED.question_text,
                   fun_fact      = EXCLUDED.fun_fact,
                   subject       = EXCLUDED.subject`,
            [date, gradeLevel, language, slot, parsed.question, parsed.fun_fact || null, parsed.subject || 'Other']
        );

        return {
            question_text: parsed.question,
            fun_fact: parsed.fun_fact || null,
            subject: parsed.subject || 'Other',
        };
    }

    async _ensureTable() {
        // Skip heavy DDL if already applied
        const migCheck = await db.query(
            `SELECT 1 FROM migration_history WHERE migration_name = 'daily_questions_v2'`
        ).catch(() => ({ rows: [] }));  // table may not exist yet on fresh DB

        if (migCheck.rows.length > 0) return;

        // Create table (new deployments)
        await db.query(`
            CREATE TABLE IF NOT EXISTS daily_questions (
                id SERIAL PRIMARY KEY,
                question_date DATE NOT NULL,
                grade_level INTEGER NOT NULL CHECK (grade_level >= 0 AND grade_level <= 14),
                language VARCHAR(20) NOT NULL DEFAULT 'en',
                time_slot INTEGER NOT NULL DEFAULT 0,
                question_text TEXT NOT NULL,
                fun_fact TEXT,
                subject VARCHAR(100),
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            )
        `);

        // Add language column if table existed without it (existing deployments)
        await db.query(`
            ALTER TABLE daily_questions
            ADD COLUMN IF NOT EXISTS language VARCHAR(20) NOT NULL DEFAULT 'en'
        `);

        // Add time_slot column if table existed without it
        await db.query(`
            ALTER TABLE daily_questions
            ADD COLUMN IF NOT EXISTS time_slot INTEGER NOT NULL DEFAULT 0
        `);

        // Migrate unique constraint to 4-column (date, slot, grade, language)
        await db.query(`
            DO $$
            BEGIN
                -- Drop old 2-column constraint if it exists
                IF EXISTS (
                    SELECT 1 FROM pg_constraint
                    WHERE conname = 'daily_questions_question_date_grade_level_key'
                ) THEN
                    ALTER TABLE daily_questions
                    DROP CONSTRAINT daily_questions_question_date_grade_level_key;
                END IF;
                -- Drop old 3-column constraint if it exists
                IF EXISTS (
                    SELECT 1 FROM pg_constraint
                    WHERE conname = 'daily_questions_date_grade_lang_key'
                ) THEN
                    ALTER TABLE daily_questions
                    DROP CONSTRAINT daily_questions_date_grade_lang_key;
                END IF;
                -- Add new 4-column constraint if not yet present
                IF NOT EXISTS (
                    SELECT 1 FROM pg_constraint
                    WHERE conname = 'daily_questions_date_slot_grade_lang_key'
                ) THEN
                    ALTER TABLE daily_questions
                    ADD CONSTRAINT daily_questions_date_slot_grade_lang_key
                    UNIQUE (question_date, time_slot, grade_level, language);
                END IF;
            END $$;
        `);

        await db.query(`
            CREATE INDEX IF NOT EXISTS idx_daily_questions_date_slot_grade_lang
                ON daily_questions(question_date, time_slot, grade_level, language)
        `);

        // Mark migration so subsequent boots skip all the DDL above
        await db.query(`
            INSERT INTO migration_history (migration_name)
            VALUES ('daily_questions_v2')
            ON CONFLICT (migration_name) DO NOTHING
        `);
    }

    /**
     * Generate a personalized "Did you know?" fact based on the student's recent subjects.
     * seenPreviews: array of previously shown question strings (exclusion list for the AI).
     * NOT stored in DB here — caller is responsible for persisting.
     */
    async generatePersonalized(gradeLevel, language = 'en', recentSubjects = [], seenPreviews = []) {
        const gradeLabel = GRADE_LABELS[gradeLevel] || `Grade ${gradeLevel}`;
        const langLabel  = LANGUAGE_LABELS[language] || language;

        const subjectContext = recentSubjects.length > 0
            ? `The student has recently been studying: ${recentSubjects.join(', ')}.\nGenerate a surprising fact RELATED to one of these subjects.`
            : 'Pick any engaging topic: science, history, nature, technology, art, culture, sports, math.';

        const seenContext = seenPreviews.length > 0
            ? `\nIMPORTANT: The student has ALREADY SEEN the following questions. You MUST generate a question about a COMPLETELY DIFFERENT topic — do NOT repeat or rephrase any of these:\n${seenPreviews.map((q, i) => `${i + 1}. ${q}`).join('\n')}`
            : '';

        const prompt = `You are generating a fun "Did you know?" question IN ${langLabel} for students in ${gradeLabel}.

${subjectContext}${seenContext}

The question should:
- Be written entirely in ${langLabel}
- Be genuinely surprising or counterintuitive
- Be age-appropriate and engaging
- Be phrased naturally in ${langLabel} (e.g. "你知道吗..." for Chinese, "Wusstest du..." for German)

Respond ONLY with valid JSON (no markdown, no code block):
{
  "question": "<question in ${langLabel}>",
  "fun_fact": "<one sentence explanation in ${langLabel}>",
  "subject": "<one of the student's recent subjects, or Science|History|Nature|Technology|Art|Sports|Math|Other>"
}`;

        logger.debug(`🤖 [DailyQuestion] Personalized OpenAI call — grade=${gradeLevel}, lang=${language}, subjects=[${recentSubjects.join(', ')}], excludes=${seenPreviews.length}`);

        const response = await this.openai.chat.completions.create({
            model: 'gpt-4o-mini',
            messages: [{ role: 'user', content: prompt }],
            max_tokens: 250,
            temperature: 1.0,
        });

        const raw = response.choices[0].message.content.trim();
        logger.debug(`📨 [DailyQuestion] Personalized response: ${raw}`);

        let parsed;
        try {
            parsed = JSON.parse(raw);
        } catch {
            logger.warn('⚠️ [DailyQuestion] Personalized JSON parse failed — using raw text');
            parsed = { question: raw, fun_fact: null, subject: 'Other' };
        }

        return {
            question_text: parsed.question,
            fun_fact: parsed.fun_fact || null,
            subject: parsed.subject || 'Other',
        };
    }

    // ──────────────────────────────────────────────────────────────
    // Seen-question history helpers (per-user dedup across sessions)
    // ──────────────────────────────────────────────────────────────

    /** Ensure the user_seen_daily_questions table exists (idempotent). */
    async _ensureSeenTable() {
        const migCheck = await db.query(
            `SELECT 1 FROM migration_history WHERE migration_name = 'user_seen_daily_questions_v1'`
        ).catch(() => ({ rows: [] }));

        if (migCheck.rows.length > 0) return;

        await db.query(`
            CREATE TABLE IF NOT EXISTS user_seen_daily_questions (
                id SERIAL PRIMARY KEY,
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                question_hash VARCHAR(32) NOT NULL,
                question_preview TEXT NOT NULL,
                shown_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                UNIQUE(user_id, question_hash)
            )
        `);

        await db.query(`
            CREATE INDEX IF NOT EXISTS idx_user_seen_daily_q_user_time
                ON user_seen_daily_questions(user_id, shown_at DESC)
        `);

        await db.query(`
            INSERT INTO migration_history (migration_name)
            VALUES ('user_seen_daily_questions_v1')
            ON CONFLICT (migration_name) DO NOTHING
        `);

        logger.info('✅ [DailyQuestion] user_seen_daily_questions table ready');
    }

    /** Return the last `limit` question previews + hashes for a user. */
    async getSeenQuestions(userId, limit = 50) {
        try {
            const result = await db.query(
                `SELECT question_hash, question_preview
                 FROM user_seen_daily_questions
                 WHERE user_id = $1
                 ORDER BY shown_at DESC
                 LIMIT $2`,
                [userId, limit]
            );
            return result.rows;
        } catch {
            return [];
        }
    }

    /**
     * Record that a question was shown to a user.
     * Silently no-ops if the table doesn't exist yet (prevents startup errors).
     * Trims history to most recent 50 entries.
     */
    async recordSeenQuestion(userId, questionText) {
        try {
            const hash = crypto.createHash('md5').update(questionText).digest('hex');
            const preview = questionText.substring(0, 150);

            await db.query(
                `INSERT INTO user_seen_daily_questions (user_id, question_hash, question_preview, shown_at)
                 VALUES ($1, $2, $3, NOW())
                 ON CONFLICT (user_id, question_hash) DO UPDATE SET shown_at = NOW()`,
                [userId, hash, preview]
            );

            // Trim to most recent 50 per user
            await db.query(
                `DELETE FROM user_seen_daily_questions
                 WHERE user_id = $1
                   AND id NOT IN (
                       SELECT id FROM user_seen_daily_questions
                       WHERE user_id = $1
                       ORDER BY shown_at DESC
                       LIMIT 50
                   )`,
                [userId]
            );

            return hash;
        } catch (err) {
            logger.warn(`⚠️ [DailyQuestion] recordSeenQuestion failed (non-fatal): ${err.message}`);
            return null;
        }
    }

    /** Returns the current 6-hour time slot (0=00:00–05:59, 1=06:00–11:59, 2=12:00–17:59, 3=18:00–23:59 UTC). */
    _currentSlot() {
        return Math.floor(new Date().getUTCHours() / 6);
    }

    _todayUTC() {
        return new Date().toISOString().split('T')[0];
    }
}

const dailyQuestionService = new DailyQuestionService();

module.exports = { DailyQuestionService, dailyQuestionService, detectLanguage };
