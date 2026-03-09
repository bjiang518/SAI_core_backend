/**
 * Daily Question Service for StudyAI
 * Generates one age-appropriate fun question per grade level per language per day.
 * 15 grades × 7 languages = 105 questions/day (gpt-4o-mini, ~$0.01/day total).
 */

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
            logger.debug('✅ [DailyQuestion] Table ready');

            this.cronJob = cron.schedule('0 6 * * *', async () => {
                logger.debug('⏰ [DailyQuestion] Cron fired — starting daily generation (06:00 UTC)');
                await this._generateAll();
            }, { scheduled: true, timezone: 'UTC' });

            logger.debug(`🕕 [DailyQuestion] Cron scheduled at 06:00 UTC (${GRADE_LABELS.length} grades × ${SUPPORTED_LANGUAGES.length} languages = ${GRADE_LABELS.length * SUPPORTED_LANGUAGES.length} questions/day)`);

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
     * Return today's question for a given grade + language.
     * Triggers on-demand generation if not yet in DB.
     */
    async getTodayQuestion(gradeLevel, language = 'en') {
        const lang = SUPPORTED_LANGUAGES.includes(language) ? language : 'en';
        const today = this._todayUTC();
        logger.debug(`🔍 [DailyQuestion] getTodayQuestion — grade=${gradeLevel}, lang=${lang}, date=${today}`);

        const result = await db.query(
            'SELECT question_text, fun_fact, subject FROM daily_questions WHERE question_date = $1 AND grade_level = $2 AND language = $3',
            [today, gradeLevel, lang]
        );

        if (result.rows.length > 0) {
            const q = result.rows[0];
            logger.debug(`📦 [DailyQuestion] Cache hit — grade=${gradeLevel}, lang=${lang}, subject=${q.subject}`);
            logger.debug(`   question: "${q.question_text}"`);
            return q;
        }

        logger.debug(`📝 [DailyQuestion] Cache miss — generating on-demand for grade=${gradeLevel}, lang=${lang}`);
        return await this._generateForGrade(gradeLevel, today, lang);
    }

    async triggerManualGeneration() {
        logger.debug('🔧 [DailyQuestion] Manual generation triggered — force=true');
        await this._generateAll(true);
    }

    getStatus() {
        return {
            isInitialized: this.isInitialized,
            generationInProgress: this.generationInProgress,
            nextGenerationTime: '06:00 UTC daily',
            gradeLevels: GRADE_LABELS.length,
            languages: SUPPORTED_LANGUAGES,
            totalPerDay: GRADE_LABELS.length * SUPPORTED_LANGUAGES.length,
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
        const total = GRADE_LABELS.length * SUPPORTED_LANGUAGES.length;

        logger.debug(`\n${'─'.repeat(60)}`);
        logger.debug(`📚 [DailyQuestion] === GENERATION START ===`);
        logger.debug(`   Date     : ${today}`);
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
                            'SELECT 1 FROM daily_questions WHERE question_date=$1 AND grade_level=$2 AND language=$3',
                            [today, grade, lang]
                        );
                        if (exists.rows.length > 0) {
                            logger.debug(`   ⏭️  Grade ${String(grade).padStart(2)} — already exists`);
                            skipped++;
                            continue;
                        }
                    }

                    try {
                        const q = await this._generateForGrade(grade, today, lang);
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

    async _generateForGrade(gradeLevel, date, language) {
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

        logger.debug(`   🤖 [DailyQuestion] OpenAI call — grade=${gradeLevel}, lang=${language}`);

        const response = await this.openai.chat.completions.create({
            model: 'gpt-4o-mini',
            messages: [{ role: 'user', content: prompt }],
            max_tokens: 250,
            temperature: 1.0,
        });

        const raw = response.choices[0].message.content.trim();
        logger.debug(`   📨 [DailyQuestion] Raw response (grade=${gradeLevel}, lang=${language}): ${raw}`);

        let parsed;
        try {
            parsed = JSON.parse(raw);
        } catch {
            logger.warn(`   ⚠️ [DailyQuestion] JSON parse failed — using raw text`);
            parsed = { question: raw, fun_fact: null, subject: 'Other' };
        }

        await db.query(
            `INSERT INTO daily_questions (question_date, grade_level, language, question_text, fun_fact, subject)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (question_date, grade_level, language) DO UPDATE
               SET question_text = EXCLUDED.question_text,
                   fun_fact      = EXCLUDED.fun_fact,
                   subject       = EXCLUDED.subject`,
            [date, gradeLevel, language, parsed.question, parsed.fun_fact || null, parsed.subject || 'Other']
        );

        return {
            question_text: parsed.question,
            fun_fact: parsed.fun_fact || null,
            subject: parsed.subject || 'Other',
        };
    }

    async _ensureTable() {
        // Create table (new deployments)
        await db.query(`
            CREATE TABLE IF NOT EXISTS daily_questions (
                id SERIAL PRIMARY KEY,
                question_date DATE NOT NULL,
                grade_level INTEGER NOT NULL CHECK (grade_level >= 0 AND grade_level <= 14),
                language VARCHAR(20) NOT NULL DEFAULT 'en',
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

        // Migrate unique constraint: (date, grade) → (date, grade, language)
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
                -- Add new 3-column constraint if not yet present
                IF NOT EXISTS (
                    SELECT 1 FROM pg_constraint
                    WHERE conname = 'daily_questions_date_grade_lang_key'
                ) THEN
                    ALTER TABLE daily_questions
                    ADD CONSTRAINT daily_questions_date_grade_lang_key
                    UNIQUE (question_date, grade_level, language);
                END IF;
            END $$;
        `);

        await db.query(`
            CREATE INDEX IF NOT EXISTS idx_daily_questions_date_grade_lang
                ON daily_questions(question_date, grade_level, language)
        `);
    }

    _todayUTC() {
        return new Date().toISOString().split('T')[0];
    }
}

const dailyQuestionService = new DailyQuestionService();

module.exports = { DailyQuestionService, dailyQuestionService, detectLanguage };
