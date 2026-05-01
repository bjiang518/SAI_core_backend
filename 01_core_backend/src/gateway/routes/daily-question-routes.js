/**
 * Daily Question Routes
 * GET /api/daily/question  — returns today's fun question in the user's language
 *
 * Language detection: parses Accept-Language header (sent automatically by iOS URLSession).
 * Supported: en, zh-Hans, zh-Hant, de, es, fr, ja
 */

const AuthHelper = require('./ai/utils/auth-helper');
const { dailyQuestionService, detectLanguage } = require('../../services/daily-question-service');
const { db } = require('../../utils/railway-database');

class DailyQuestionRoutes {
    constructor(fastify) {
        this.fastify = fastify;
        this.authHelper = new AuthHelper(fastify);
    }

    registerRoutes() {
        this.fastify.get('/api/daily/question', this._getQuestion.bind(this));
        this.fastify.get('/api/daily/question/personalized', this._getPersonalizedQuestion.bind(this));
        this.fastify.post('/admin/daily-question/generate', this._adminGenerate.bind(this));
        this.fastify.get('/admin/daily-question/status', this._adminStatus.bind(this));
    }

    async _getQuestion(request, reply) {
        const userId = await this.authHelper.requireAuth(request, reply);
        if (!userId) return;

        const shortId = String(userId).substring(0, 8);

        try {
            // Prefer explicit ?lang= param (set by iOS from user's in-app language setting)
            // over Accept-Language header (which reflects the device's system language).
            const langParam = request.query?.lang;
            const language = langParam
                ? detectLanguage(langParam)  // validate + normalize
                : detectLanguage(request.headers['accept-language']);

            // Look up user's grade level and display name
            const profileResult = await db.query(
                'SELECT grade_level, display_name FROM profiles WHERE user_id = $1',
                [userId]
            );
            const profile     = profileResult.rows[0];
            const gradeLevel  = profile?.grade_level  ?? 6;
            const displayName = profile?.display_name ?? 'unknown';

            this.fastify.log.info(
                `📬 [DailyQuestion] Request — user=${shortId}... (${displayName}), grade=${gradeLevel}, lang=${language}, Accept-Language: "${request.headers['accept-language'] ?? 'none'}"`
            );

            const question = await dailyQuestionService.getTodayQuestion(gradeLevel, language);

            if (!question) {
                this.fastify.log.warn(
                    `⚠️ [DailyQuestion] No question available — user=${shortId}..., grade=${gradeLevel}, lang=${language}`
                );
                return reply.status(404).send({ success: false, message: 'No question available for today' });
            }

            const today = new Date().toISOString().split('T')[0];
            const timeSlot = Math.floor(new Date().getUTCHours() / 6);
            this.fastify.log.info(
                `✅ [DailyQuestion] Served — user=${shortId}... (${displayName}), grade=${gradeLevel}, lang=${language}, subject=${question.subject}`
            );
            this.fastify.log.info(`   question : "${question.question_text}"`);
            this.fastify.log.info(`   fun_fact : "${question.fun_fact ?? '(none)'}"`);

            return reply.send({
                success: true,
                data: {
                    question:    question.question_text,
                    fun_fact:    question.fun_fact,
                    subject:     question.subject,
                    grade_level: gradeLevel,
                    language,
                    date:        today,
                    time_slot:   timeSlot,
                },
            });
        } catch (error) {
            this.fastify.log.error(`❌ [DailyQuestion] Error for user=${shortId}...:`, error);
            return reply.status(500).send({ success: false, message: 'Failed to fetch daily question' });
        }
    }

    async _getPersonalizedQuestion(request, reply) {
        const userId = await this.authHelper.requireAuth(request, reply);
        if (!userId) return;

        const shortId = String(userId).substring(0, 8);

        try {
            const langParam = request.query?.lang;
            const language = langParam
                ? detectLanguage(langParam)
                : detectLanguage(request.headers['accept-language']);

            // Look up user's grade level
            const profileResult = await db.query(
                'SELECT grade_level, display_name FROM profiles WHERE user_id = $1',
                [userId]
            );
            const profile     = profileResult.rows[0];
            const gradeLevel  = profile?.grade_level  ?? 6;
            const displayName = profile?.display_name ?? 'unknown';

            // Gather recent subjects from sessions (last 14 days)
            const convResult = await db.query(
                `SELECT DISTINCT subject FROM sessions
                 WHERE user_id = $1 AND start_time > NOW() - INTERVAL '14 days' AND subject IS NOT NULL AND subject != 'general'
                 LIMIT 5`,
                [userId]
            );
            const convSubjects = convResult.rows.map(r => r.subject);

            // Also extract subjects from short_term_status weaknesses (format: "Subject/concept/type")
            const stsResult = await db.query(
                `SELECT active_weaknesses FROM short_term_status WHERE user_id = $1`,
                [userId]
            );
            const weaknessSubjects = [];
            if (stsResult.rows.length > 0 && stsResult.rows[0].active_weaknesses) {
                const weaknesses = stsResult.rows[0].active_weaknesses;
                for (const key of Object.keys(weaknesses)) {
                    const subject = key.split('/')[0];
                    if (subject) weaknessSubjects.push(subject);
                }
            }

            // Merge + deduplicate
            const recentSubjects = [...new Set([...convSubjects, ...weaknessSubjects])].slice(0, 8);

            // Fetch user's seen-question history (last 30) for dedup
            const seenRows = await dailyQuestionService.getSeenQuestions(userId, 30);
            const seenPreviews = seenRows.map(r => r.question_preview);
            const seenHashes   = new Set(seenRows.map(r => r.question_hash));

            this.fastify.log.info(
                `📬 [DailyQuestion] Personalized — user=${shortId}... (${displayName}), grade=${gradeLevel}, lang=${language}, subjects=[${recentSubjects.join(', ')}], seen=${seenPreviews.length}`
            );

            let question = await dailyQuestionService.generatePersonalized(gradeLevel, language, recentSubjects, seenPreviews);

            // Hash-based safety net: if AI still produced an exact duplicate, retry once
            if (question) {
                const crypto = require('crypto');
                const newHash = crypto.createHash('md5').update(question.question_text).digest('hex');
                if (seenHashes.has(newHash)) {
                    this.fastify.log.warn(`⚠️ [DailyQuestion] Exact duplicate detected for user=${shortId}..., retrying with stronger exclusion`);
                    question = await dailyQuestionService.generatePersonalized(gradeLevel, language, recentSubjects, seenPreviews);
                }
            }

            if (!question) {
                return reply.status(500).send({ success: false, message: 'Failed to generate personalized question' });
            }

            // Persist to seen history (non-blocking — failure is non-fatal)
            dailyQuestionService.recordSeenQuestion(userId, question.question_text).catch(() => {});

            this.fastify.log.info(
                `✅ [DailyQuestion] Personalized served — user=${shortId}..., subject=${question.subject}`
            );

            return reply.send({
                success: true,
                data: {
                    question:    question.question_text,
                    fun_fact:    question.fun_fact,
                    subject:     question.subject,
                    grade_level: gradeLevel,
                    language,
                    date:        new Date().toISOString().split('T')[0],
                    time_slot:   Math.floor(new Date().getUTCHours() / 6),
                },
            });
        } catch (error) {
            this.fastify.log.error(`❌ [DailyQuestion] Personalized error for user=${shortId}...:`, error);
            return reply.status(500).send({ success: false, message: 'Failed to generate personalized question' });
        }
    }

    async _adminGenerate(request, reply) {
        this.fastify.log.info('🔧 [DailyQuestion] Admin: manual generation triggered');
        try {
            await dailyQuestionService.triggerManualGeneration();
            const today = new Date().toISOString().split('T')[0];
            const result = await db.query(
                `SELECT grade_level, language, subject, question_text, fun_fact
                 FROM daily_questions WHERE question_date = $1
                 ORDER BY language, grade_level`,
                [today]
            );
            this.fastify.log.info(`🔧 [DailyQuestion] Admin: done — ${result.rows.length} rows for ${today}`);
            return reply.send({
                success: true,
                message: `Generated ${result.rows.length} questions for ${today}`,
                timestamp: new Date().toISOString(),
                questions: result.rows,
            });
        } catch (error) {
            this.fastify.log.error('❌ [DailyQuestion] Admin generation failed:', error);
            return reply.status(500).send({ success: false, message: error.message });
        }
    }

    async _adminStatus(request, reply) {
        const today = new Date().toISOString().split('T')[0];
        const result = await db.query(
            `SELECT grade_level, language, subject, question_text
             FROM daily_questions WHERE question_date = $1
             ORDER BY language, grade_level`,
            [today]
        ).catch(() => ({ rows: [] }));

        // Group by language for easier reading
        const byLanguage = {};
        for (const row of result.rows) {
            if (!byLanguage[row.language]) byLanguage[row.language] = [];
            byLanguage[row.language].push({ grade: row.grade_level, subject: row.subject, question: row.question_text });
        }

        return reply.send({
            success: true,
            data: {
                ...dailyQuestionService.getStatus(),
                today,
                generatedToday: result.rows.length,
                byLanguage,
            },
            timestamp: new Date().toISOString(),
        });
    }
}

module.exports = DailyQuestionRoutes;
