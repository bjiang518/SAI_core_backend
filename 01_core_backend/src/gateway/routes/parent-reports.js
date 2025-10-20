/**
 * StudyAI Parent Reports API Routes
 * Handles parent report generation, retrieval, and management
 */

const ReportDataAggregationService = require('../../services/report-data-aggregation');
const ReportExportService = require('../../services/report-export-service');
const ReportNarrativeService = require('../../services/report-narrative-service');
const { db } = require('../../utils/railway-database');

class ParentReportsRoutes {
    constructor(fastify) {
        this.fastify = fastify;
        this.reportService = new ReportDataAggregationService();
        this.exportService = new ReportExportService();
        this.narrativeService = new ReportNarrativeService();
        this.setupRoutes();
    }

    setupRoutes() {
        // Generate new parent report
        this.fastify.post('/api/reports/generate', {
            schema: {
                description: 'Generate comprehensive parent report for student',
                tags: ['Reports'],
                body: {
                    type: 'object',
                    required: ['student_id', 'start_date', 'end_date'],
                    properties: {
                        student_id: { type: 'string', format: 'uuid' },
                        start_date: { type: 'string', format: 'date' },
                        end_date: { type: 'string', format: 'date' },
                        report_type: {
                            type: 'string',
                            enum: ['weekly', 'monthly', 'custom', 'progress'],
                            default: 'custom'
                        },
                        include_ai_analysis: { type: 'boolean', default: true },
                        compare_with_previous: { type: 'boolean', default: true },
                        aggregated_data: {
                            type: 'object',
                            description: 'Pre-aggregated data from iOS client (local-first approach)',
                            additionalProperties: true
                        }
                    }
                },
                response: {
                    200: {
                        type: 'object',
                        properties: {
                            success: { type: 'boolean' },
                            report_id: { type: 'string' },
                            report_data: { type: 'object' },
                            generation_time_ms: { type: 'number' },
                            expires_at: { type: 'string' }
                        }
                    }
                }
            }
        }, this.generateReport.bind(this));

        // Get existing report by ID
        this.fastify.get('/api/reports/:reportId', {
            schema: {
                description: 'Retrieve existing parent report',
                tags: ['Reports'],
                params: {
                    type: 'object',
                    properties: {
                        reportId: { type: 'string', format: 'uuid' }
                    }
                }
            }
        }, this.getReport.bind(this));

        // List reports for a student
        this.fastify.get('/api/reports/student/:studentId', {
            schema: {
                description: 'List all reports for a student',
                tags: ['Reports'],
                params: {
                    type: 'object',
                    properties: {
                        studentId: { type: 'string', format: 'uuid' }
                    }
                },
                querystring: {
                    type: 'object',
                    properties: {
                        limit: { type: 'integer', minimum: 1, maximum: 100, default: 20 },
                        offset: { type: 'integer', minimum: 0, default: 0 },
                        report_type: { type: 'string', enum: ['weekly', 'monthly', 'custom', 'progress'] }
                    }
                }
            }
        }, this.getStudentReports.bind(this));

        // Get report generation status
        this.fastify.get('/api/reports/:reportId/status', {
            schema: {
                description: 'Get report generation status',
                tags: ['Reports'],
                params: {
                    type: 'object',
                    properties: {
                        reportId: { type: 'string', format: 'uuid' }
                    }
                }
            }
        }, this.getReportStatus.bind(this));

        // Export report to PDF
        this.fastify.get('/api/reports/:reportId/export', {
            schema: {
                description: 'Export report as PDF',
                tags: ['Reports'],
                params: {
                    type: 'object',
                    properties: {
                        reportId: { type: 'string', format: 'uuid' }
                    }
                },
                querystring: {
                    type: 'object',
                    properties: {
                        format: { type: 'string', enum: ['pdf', 'json'], default: 'pdf' }
                    }
                }
            }
        }, this.exportReport.bind(this));

        // Email report to recipients
        this.fastify.post('/api/reports/:reportId/email', {
            schema: {
                description: 'Email report to specified recipients',
                tags: ['Reports'],
                params: {
                    type: 'object',
                    properties: {
                        reportId: { type: 'string', format: 'uuid' }
                    }
                },
                body: {
                    type: 'object',
                    required: ['to'],
                    properties: {
                        to: {
                            type: 'array',
                            items: { type: 'string', format: 'email' },
                            minItems: 1,
                            maxItems: 5
                        },
                        subject: { type: 'string' },
                        message: { type: 'string' }
                    }
                }
            }
        }, this.emailReport.bind(this));

        // Generate shareable link
        this.fastify.post('/api/reports/:reportId/share', {
            schema: {
                description: 'Generate shareable link for report',
                tags: ['Reports'],
                params: {
                    type: 'object',
                    properties: {
                        reportId: { type: 'string', format: 'uuid' }
                    }
                },
                body: {
                    type: 'object',
                    properties: {
                        expiryDays: { type: 'integer', minimum: 1, maximum: 30, default: 7 },
                        maxAccess: { type: 'integer', minimum: 1, maximum: 100 },
                        password: { type: 'string' }
                    }
                }
            }
        }, this.generateShareLink.bind(this));

        // Get human-readable narrative report
        this.fastify.get('/api/reports/:reportId/narrative', {
            schema: {
                description: 'Get human-readable narrative report',
                tags: ['Reports'],
                params: {
                    type: 'object',
                    properties: {
                        reportId: { type: 'string', format: 'uuid' }
                    }
                },
                response: {
                    200: {
                        type: 'object',
                        properties: {
                            success: { type: 'boolean' },
                            narrative: {
                                type: 'object',
                                properties: {
                                    id: { type: 'string' },
                                    content: { type: 'string' },
                                    summary: { type: 'string' },
                                    keyInsights: { type: 'array' },
                                    recommendations: { type: 'array' },
                                    wordCount: { type: 'number' },
                                    generatedAt: { type: 'string' }
                                }
                            }
                        }
                    }
                }
            }
        }, this.getNarrative.bind(this));

        // List narrative reports for a student
        this.fastify.get('/api/reports/student/:studentId/narratives', {
            schema: {
                description: 'List narrative reports for a student',
                tags: ['Reports'],
                params: {
                    type: 'object',
                    properties: {
                        studentId: { type: 'string', format: 'uuid' }
                    }
                },
                querystring: {
                    type: 'object',
                    properties: {
                        limit: { type: 'integer', minimum: 1, maximum: 50, default: 10 },
                        offset: { type: 'integer', minimum: 0, default: 0 }
                    }
                }
            }
        }, this.getStudentNarratives.bind(this));

        // Delete expired reports (cleanup endpoint)
        this.fastify.delete('/api/reports/cleanup', {
            schema: {
                description: 'Clean up expired reports',
                tags: ['Reports']
            }
        }, this.cleanupExpiredReports.bind(this));

        // Get report analytics/metrics
        this.fastify.get('/api/reports/analytics', {
            schema: {
                description: 'Get report generation analytics',
                tags: ['Reports']
            }
        }, this.getReportAnalytics.bind(this));
    }


    /**
     * Generate new parent report
     */
    async generateReport(request, reply) {
        const startTime = Date.now();

        try {
            this.fastify.log.info('🎯 === PARENT REPORT GENERATION REQUEST ===');
            this.fastify.log.info(`📋 Request body: ${JSON.stringify(request.body, null, 2)}`);

            // Get authenticated user ID
            const authenticatedUserId = await this.getUserIdFromToken(request);
            this.fastify.log.info(`🔐 Authenticated user ID: ${authenticatedUserId || 'null'}`);

            if (!authenticatedUserId) {
                this.fastify.log.warn('❌ Authentication failed - no valid token');
                return reply.status(401).send({
                    success: false,
                    error: 'Authentication required to generate reports',
                    code: 'AUTHENTICATION_REQUIRED'
                });
            }

            const { student_id, start_date, end_date, report_type, include_ai_analysis, compare_with_previous, aggregated_data } = request.body;

            this.fastify.log.info(`📊 Report parameters:`);
            this.fastify.log.info(`   - Student ID: ${student_id}`);
            this.fastify.log.info(`   - Date range: ${start_date} to ${end_date}`);
            this.fastify.log.info(`   - Report type: ${report_type}`);
            this.fastify.log.info(`   - Include AI analysis: ${include_ai_analysis}`);
            this.fastify.log.info(`   - Compare with previous: ${compare_with_previous}`);
            this.fastify.log.info(`   - Pre-aggregated data provided: ${!!aggregated_data}`);

            // Verify user has access to this student's data
            const hasAccess = await this.verifyStudentAccess(authenticatedUserId, student_id);
            this.fastify.log.info(`🔒 Access verification result: ${hasAccess}`);

            if (!hasAccess) {
                this.fastify.log.warn(`❌ Access denied for user ${authenticatedUserId} to student ${student_id}`);
                return reply.status(403).send({
                    success: false,
                    error: 'Access denied to student data',
                    code: 'ACCESS_DENIED'
                });
            }

            this.fastify.log.info(`📊 Generating ${report_type} report for student: ${student_id}`);
            this.fastify.log.info(`📅 Date range: ${start_date} to ${end_date}`);

            // Parse dates
            const startDate = new Date(start_date);
            const endDate = new Date(end_date);

            this.fastify.log.info(`📅 Parsed dates: ${startDate.toISOString()} to ${endDate.toISOString()}`);

            // Validate date range
            if (startDate >= endDate) {
                this.fastify.log.warn(`❌ Invalid date range: start ${startDate} >= end ${endDate}`);
                return reply.status(400).send({
                    success: false,
                    error: 'Start date must be before end date',
                    code: 'INVALID_DATE_RANGE'
                });
            }

            // Check for existing recent report with smart time-based caching
            this.fastify.log.info('🔍 Checking for existing cached report...');

            const existingReport = await this.findExistingReportWithTimeLogic(student_id, startDate, endDate, report_type);

            if (existingReport) {
                this.fastify.log.info(`📋 Found cached report: ${existingReport.id}`);
                this.fastify.log.info('📈 Report viewed (metrics logging only)');

                // Log view action (database storage removed in migration 005)

                // Get the cached report's narrative
                const cachedNarrative = await this.narrativeService.getNarrativeByReportId(existingReport.id);

                // Create minimal report_data structure for cached response
                const responsePayload = {
                    success: true,
                    report_id: existingReport.id,
                    report_data: {
                        type: "narrative_report",
                        narrative_available: cachedNarrative ? true : false,
                        narrative_id: cachedNarrative ? cachedNarrative.id : null,
                        url: `/api/reports/${existingReport.id}/narrative`
                    },
                    cached: true
                };

                return reply.send(responsePayload);
            }

            this.fastify.log.info('🚀 No cached report found, generating new report...');

            // ✅ NEW: Check if iOS provided pre-aggregated data (local-first approach)
            let reportData;

            if (aggregated_data) {
                // Use pre-aggregated data from iOS (skip database queries)
                this.fastify.log.info('📱 Using pre-aggregated data from iOS client (LOCAL-FIRST)');
                this.fastify.log.info(`📊 Data summary: ${aggregated_data.academic?.totalQuestions || 0} questions, ${aggregated_data.activity?.studyTime?.activeDays || 0} active days`);
                reportData = aggregated_data;

            } else {
                // Fallback: Generate report data from server database (legacy approach)
                this.fastify.log.info('📊 Starting server-side report data aggregation (database queries)...');
                reportData = await this.reportService.aggregateReportData(student_id, startDate, endDate, {
                    includeAIInsights: include_ai_analysis,
                    comparePrevious: compare_with_previous
                });
            }

            this.fastify.log.info('✅ Report data ready for narrative generation');
            this.fastify.log.info(`📈 Report summary: ${JSON.stringify({
                totalQuestions: reportData.metadata?.dataPoints?.questions || 0,
                totalSessions: reportData.metadata?.dataPoints?.sessions || 0,
                totalConversations: reportData.metadata?.dataPoints?.conversations || 0,
                generationTimeMs: reportData.metadata?.generationTimeMs || 0
            })}`);

            // Store report in database
            this.fastify.log.info('💾 Storing report in database...');
            const reportId = await this.storeReport({
                userId: student_id,
                reportType: report_type,
                startDate,
                endDate,
                reportData,
                generationTimeMs: Date.now() - startTime,
                aiAnalysisIncluded: include_ai_analysis
            });

            this.fastify.log.info(`💾 Report stored with ID: ${reportId}`);

            // Log report metrics (database storage removed in migration 005)
            this.fastify.log.info('📊 Report metrics:', {
                reportId,
                dataFetchTime: reportData.metadata.generationTimeMs,
                totalGenerationTime: Date.now() - startTime,
                questionsAnalyzed: reportData.metadata.dataPoints.questions,
                conversationsAnalyzed: reportData.metadata.dataPoints.conversations,
                sessionsAnalyzed: reportData.metadata.dataPoints.sessions,
                mentalHealthIndicatorsCount: reportData.metadata.dataPoints.mentalHealthIndicators
            });

            // Log progress history (database storage removed in migration 005)
            this.fastify.log.info('📈 Progress history logged for report:', reportId);

            // Generate human-readable narrative
            this.fastify.log.info('📝 Generating human-readable narrative...');
            let narrativeResult = null;
            try {
                narrativeResult = await this.narrativeService.generateNarrative(reportId, reportData);
                this.fastify.log.info(`📝 Narrative generated: ${narrativeResult.id}`);
            } catch (narrativeError) {
                this.fastify.log.warn(`⚠️ Narrative generation failed: ${narrativeError.message}`);
                // Continue without narrative - it's not critical for the main response
            }

            const duration = Date.now() - startTime;
            this.fastify.log.info(`✅ Report generation completed in ${duration}ms`);

            // Create minimal response to avoid proxy truncation
            const responsePayload = {
                success: true,
                report_id: reportId,
                report_data: {
                    type: "narrative_report",
                    narrative_available: !!narrativeResult,
                    url: `/api/reports/${reportId}/narrative`
                }
            };

            return reply.send(responsePayload);

        } catch (error) {
            this.fastify.log.error('❌ === REPORT GENERATION ERROR ===');
            this.fastify.log.error(`Error details: ${error.message}`);
            this.fastify.log.error(`Stack trace: ${error.stack}`);

            return reply.status(500).send({
                success: false,
                error: 'Failed to generate report',
                code: 'REPORT_GENERATION_ERROR',
                details: error.message
            });
        }
    }

    /**
     * Get existing report by ID
     */
    async getReport(request, reply) {
        try {
            const { reportId } = request.params;

            // Get authenticated user ID
            const authenticatedUserId = await this.getUserIdFromToken(request);
            if (!authenticatedUserId) {
                return reply.status(401).send({
                    success: false,
                    error: 'Authentication required',
                    code: 'AUTHENTICATION_REQUIRED'
                });
            }

            const query = `
                SELECT
                    pr.*,
                    u.name as student_name
                FROM parent_reports pr
                JOIN users u ON pr.user_id = u.id
                WHERE pr.id = $1 AND pr.status = 'completed' AND pr.expires_at > NOW()
            `;

            const result = await db.query(query, [reportId]);

            if (result.rows.length === 0) {
                return reply.status(404).send({
                    success: false,
                    error: 'Report not found or expired',
                    code: 'REPORT_NOT_FOUND'
                });
            }

            const report = result.rows[0];

            // Verify user has access to this report
            const hasAccess = await this.verifyStudentAccess(authenticatedUserId, report.user_id);
            if (!hasAccess) {
                return reply.status(403).send({
                    success: false,
                    error: 'Access denied to this report',
                    code: 'ACCESS_DENIED'
                });
            }

            // Log view action (database storage removed in migration 005)
            this.fastify.log.info(`📊 Report ${reportId} viewed`);

            return reply.send({
                success: true,
                report: {
                    id: report.id,
                    student_name: report.student_name,
                    report_type: report.report_type,
                    start_date: report.start_date,
                    end_date: report.end_date,
                    report_data: report.report_data,
                    generated_at: report.generated_at,
                    expires_at: report.expires_at,
                    ai_analysis_included: report.ai_analysis_included,
                    viewed_count: report.viewed_count || 0,
                    exported_count: report.exported_count || 0
                }
            });

        } catch (error) {
            this.fastify.log.error('Get report error:', error);
            return reply.status(500).send({
                success: false,
                error: 'Failed to retrieve report',
                code: 'REPORT_RETRIEVAL_ERROR'
            });
        }
    }

    /**
     * Get list of reports for a student
     */
    async getStudentReports(request, reply) {
        try {
            const { studentId } = request.params;
            const { limit = 20, offset = 0, report_type } = request.query;

            // Get authenticated user ID
            const authenticatedUserId = await this.getUserIdFromToken(request);
            if (!authenticatedUserId) {
                return reply.status(401).send({
                    success: false,
                    error: 'Authentication required',
                    code: 'AUTHENTICATION_REQUIRED'
                });
            }

            // Verify access
            const hasAccess = await this.verifyStudentAccess(authenticatedUserId, studentId);
            if (!hasAccess) {
                return reply.status(403).send({
                    success: false,
                    error: 'Access denied to student reports',
                    code: 'ACCESS_DENIED'
                });
            }

            let query = `
                SELECT
                    pr.id,
                    pr.report_type,
                    pr.start_date,
                    pr.end_date,
                    pr.generated_at,
                    pr.expires_at,
                    pr.ai_analysis_included,
                    pr.generation_time_ms as total_generation_time_ms
                FROM parent_reports pr
                WHERE pr.user_id = $1 AND pr.status = 'completed' AND pr.expires_at > NOW()
            `;

            const params = [studentId];

            if (report_type) {
                query += ` AND pr.report_type = $${params.length + 1}`;
                params.push(report_type);
            }

            query += ` ORDER BY pr.generated_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
            params.push(limit, offset);

            const result = await db.query(query, params);

            // Get total count
            let countQuery = `SELECT COUNT(*) as total FROM parent_reports WHERE user_id = $1 AND status = 'completed' AND expires_at > NOW()`;
            const countParams = [studentId];

            if (report_type) {
                countQuery += ` AND report_type = $2`;
                countParams.push(report_type);
            }

            const countResult = await db.query(countQuery, countParams);
            const totalReports = parseInt(countResult.rows[0].total);

            return reply.send({
                success: true,
                reports: result.rows,
                pagination: {
                    total: totalReports,
                    limit: parseInt(limit),
                    offset: parseInt(offset),
                    hasMore: offset + limit < totalReports
                }
            });

        } catch (error) {
            this.fastify.log.error('Get student reports error:', error);
            return reply.status(500).send({
                success: false,
                error: 'Failed to retrieve student reports',
                code: 'REPORTS_RETRIEVAL_ERROR'
            });
        }
    }

    /**
     * Get report generation status
     */
    async getReportStatus(request, reply) {
        try {
            const { reportId } = request.params;

            const query = `
                SELECT status, generated_at, expires_at, generation_time_ms
                FROM parent_reports
                WHERE id = $1
            `;

            const result = await db.query(query, [reportId]);

            if (result.rows.length === 0) {
                return reply.status(404).send({
                    success: false,
                    error: 'Report not found',
                    code: 'REPORT_NOT_FOUND'
                });
            }

            const report = result.rows[0];

            return reply.send({
                success: true,
                status: report.status,
                generated_at: report.generated_at,
                expires_at: report.expires_at,
                generation_time_ms: report.generation_time_ms
            });

        } catch (error) {
            this.fastify.log.error('Get report status error:', error);
            return reply.status(500).send({
                success: false,
                error: 'Failed to get report status',
                code: 'STATUS_RETRIEVAL_ERROR'
            });
        }
    }

    /**
     * Export report as PDF or JSON
     */
    async exportReport(request, reply) {
        const startTime = Date.now();

        try {
            const { reportId } = request.params;
            const { format = 'pdf' } = request.query;

            this.fastify.log.info(`📊 === REPORT EXPORT REQUEST ===`);
            this.fastify.log.info(`🆔 Report ID: ${reportId}`);
            this.fastify.log.info(`📄 Format: ${format}`);

            // Get authenticated user ID
            const authenticatedUserId = await this.getUserIdFromToken(request);
            if (!authenticatedUserId) {
                return reply.status(401).send({
                    success: false,
                    error: 'Authentication required to export reports',
                    code: 'AUTHENTICATION_REQUIRED'
                });
            }

            // Get the report data
            const query = `
                SELECT
                    pr.*,
                    u.name as student_name
                FROM parent_reports pr
                JOIN users u ON pr.user_id = u.id
                WHERE pr.id = $1 AND pr.status = 'completed' AND pr.expires_at > NOW()
            `;

            const result = await db.query(query, [reportId]);

            if (result.rows.length === 0) {
                return reply.status(404).send({
                    success: false,
                    error: 'Report not found or expired',
                    code: 'REPORT_NOT_FOUND'
                });
            }

            const report = result.rows[0];

            // Verify user has access to this report
            const hasAccess = await this.verifyStudentAccess(authenticatedUserId, report.user_id);
            if (!hasAccess) {
                return reply.status(403).send({
                    success: false,
                    error: 'Access denied to this report',
                    code: 'ACCESS_DENIED'
                });
            }

            // Log export action (database storage removed in migration 005)
            this.fastify.log.info(`📊 Report ${reportId} exported as ${format}`);

            if (format === 'json') {
                this.fastify.log.info(`✅ JSON export completed in ${Date.now() - startTime}ms`);
                return reply.send({
                    success: true,
                    report: {
                        id: report.id,
                        student_name: report.student_name,
                        report_type: report.report_type,
                        start_date: report.start_date,
                        end_date: report.end_date,
                        report_data: report.report_data,
                        generated_at: report.generated_at,
                        ai_analysis_included: report.ai_analysis_included
                    }
                });
            }

            // Generate PDF
            this.fastify.log.info(`📄 Generating PDF report...`);

            const reportData = {
                report: {
                    id: report.id,
                    student_name: report.student_name,
                    report_type: report.report_type,
                    start_date: report.start_date,
                    end_date: report.end_date,
                    generated_at: report.generated_at,
                    ai_analysis_included: report.ai_analysis_included
                },
                report_data: report.report_data
            };

            const pdfPath = await this.exportService.generatePDFReport(reportData, {
                includeCharts: true,
                includeRecommendations: true
            });

            this.fastify.log.info(`✅ PDF generated successfully: ${pdfPath}`);

            // Read the PDF file and send it
            const fs = require('fs');
            const pdfBuffer = fs.readFileSync(pdfPath);

            // Clean up the temporary file
            fs.unlinkSync(pdfPath);

            const duration = Date.now() - startTime;
            this.fastify.log.info(`✅ === REPORT EXPORT SUCCESS ===`);
            this.fastify.log.info(`⏱️ Total export time: ${duration}ms`);
            this.fastify.log.info(`📊 PDF size: ${pdfBuffer.length} bytes`);

            return reply
                .type('application/pdf')
                .header('Content-Disposition', `attachment; filename="studyai-report-${reportId}.pdf"`)
                .send(pdfBuffer);

        } catch (error) {
            this.fastify.log.error('❌ === REPORT EXPORT ERROR ===');
            this.fastify.log.error(`Error details: ${error.message}`);
            this.fastify.log.error(`Stack trace: ${error.stack}`);

            return reply.status(500).send({
                success: false,
                error: 'Failed to export report',
                code: 'EXPORT_ERROR',
                details: error.message,
                processing_time_ms: Date.now() - startTime
            });
        }
    }

    /**
     * Clean up expired reports
     */
    async cleanupExpiredReports(request, reply) {
        try {
            const query = `
                DELETE FROM parent_reports
                WHERE expires_at < NOW() AND status = 'completed'
                RETURNING id
            `;

            const result = await db.query(query);

            return reply.send({
                success: true,
                cleaned_reports: result.rows.length,
                message: `Cleaned up ${result.rows.length} expired reports`
            });

        } catch (error) {
            this.fastify.log.error('Cleanup reports error:', error);
            return reply.status(500).send({
                success: false,
                error: 'Failed to cleanup expired reports',
                code: 'CLEANUP_ERROR'
            });
        }
    }

    /**
     * Get report analytics
     */
    async getReportAnalytics(request, reply) {
        try {
            const query = `
                SELECT
                    COUNT(*) as total_reports,
                    COUNT(CASE WHEN generated_at >= NOW() - INTERVAL '7 days' THEN 1 END) as reports_last_week,
                    COUNT(CASE WHEN generated_at >= NOW() - INTERVAL '30 days' THEN 1 END) as reports_last_month,
                    AVG(generation_time_ms) as avg_generation_time,
                    COUNT(CASE WHEN ai_analysis_included = true THEN 1 END) as ai_reports_count,
                    MAX(generated_at) as last_report_generated
                FROM parent_reports
                WHERE status = 'completed'
            `;

            const result = await db.query(query);
            const analytics = result.rows[0];

            // Note: Metrics previously from report_metrics table (removed in migration 005)
            // Using zeros as these are no longer tracked in database

            return reply.send({
                success: true,
                analytics: {
                    reports: {
                        total: parseInt(analytics.total_reports),
                        lastWeek: parseInt(analytics.reports_last_week),
                        lastMonth: parseInt(analytics.reports_last_month),
                        withAIAnalysis: parseInt(analytics.ai_reports_count),
                        lastGenerated: analytics.last_report_generated
                    },
                    performance: {
                        avgGenerationTimeMs: Math.round(parseFloat(analytics.avg_generation_time) || 0),
                        avgTotalTimeMs: 0, // Removed: was from report_metrics table
                        avgQuestionsPerReport: 0, // Removed: was from report_metrics table
                        avgConversationsPerReport: 0 // Removed: was from report_metrics table
                    },
                    usage: {
                        totalViews: 0, // Removed: was from report_metrics table
                        totalExports: 0 // Removed: was from report_metrics table
                    }
                }
            });

        } catch (error) {
            this.fastify.log.error('Get analytics error:', error);
            return reply.status(500).send({
                success: false,
                error: 'Failed to retrieve analytics',
                code: 'ANALYTICS_ERROR'
            });
        }
    }

    // Helper methods

    async getUserIdFromToken(request) {
        try {
            const authHeader = request.headers.authorization;
            if (!authHeader || !authHeader.startsWith('Bearer ')) {
                return null;
            }

            const token = authHeader.substring(7);
            const sessionData = await db.verifyUserSession(token);
            return sessionData?.user_id || null;
        } catch (error) {
            this.fastify.log.error('Token verification error:', error);
            return null;
        }
    }

    async verifyStudentAccess(authenticatedUserId, studentId) {
        // For now, allow users to access their own data
        // In a real parent-student system, you'd check parent-child relationships
        return authenticatedUserId === studentId;
    }

    async findExistingReportWithTimeLogic(userId, startDate, endDate, reportType) {
        this.fastify.log.info(`🕒 Smart cache check for ${reportType} report`);
        this.fastify.log.info(`🕒 Requested period: ${startDate.toISOString()} to ${endDate.toISOString()}`);

        // For custom reports, use exact date matching (original behavior)
        if (reportType === 'custom' || reportType === 'progress') {
            this.fastify.log.info('🕒 Using exact date matching for custom/progress report');
            return await this.findExistingReport(userId, startDate, endDate, reportType);
        }

        const now = new Date();
        let shouldUseCache = false;
        let cacheReason = '';

        if (reportType === 'weekly') {
            // For weekly reports, only use cache if we're still in the same week
            const requestedWeekStart = new Date(startDate);
            const requestedWeekEnd = new Date(endDate);

            // Check if the requested period is for the current week
            const currentWeekStart = new Date(now);
            currentWeekStart.setDate(now.getDate() - now.getDay()); // Start of current week (Sunday)
            currentWeekStart.setHours(0, 0, 0, 0);

            const currentWeekEnd = new Date(currentWeekStart);
            currentWeekEnd.setDate(currentWeekStart.getDate() + 6); // End of current week (Saturday)
            currentWeekEnd.setHours(23, 59, 59, 999);

            // If requesting current week data, allow caching
            if (requestedWeekStart >= currentWeekStart && requestedWeekEnd <= currentWeekEnd) {
                shouldUseCache = true;
                cacheReason = 'Same week as current week';
            } else {
                shouldUseCache = false;
                cacheReason = 'Different week from current week';
            }

            this.fastify.log.info(`🕒 Weekly report cache decision: ${shouldUseCache ? 'USE CACHE' : 'GENERATE NEW'} - ${cacheReason}`);
            this.fastify.log.info(`🕒 Current week: ${currentWeekStart.toISOString()} to ${currentWeekEnd.toISOString()}`);
            this.fastify.log.info(`🕒 Requested week: ${requestedWeekStart.toISOString()} to ${requestedWeekEnd.toISOString()}`);

        } else if (reportType === 'monthly') {
            // For monthly reports, only use cache if we're still in the same month
            const requestedMonth = startDate.getMonth();
            const requestedYear = startDate.getFullYear();
            const currentMonth = now.getMonth();
            const currentYear = now.getFullYear();

            if (requestedMonth === currentMonth && requestedYear === currentYear) {
                shouldUseCache = true;
                cacheReason = 'Same month and year as current month';
            } else {
                shouldUseCache = false;
                cacheReason = 'Different month or year from current month';
            }

            this.fastify.log.info(`🕒 Monthly report cache decision: ${shouldUseCache ? 'USE CACHE' : 'GENERATE NEW'} - ${cacheReason}`);
            this.fastify.log.info(`🕒 Current month/year: ${currentMonth + 1}/${currentYear}`);
            this.fastify.log.info(`🕒 Requested month/year: ${requestedMonth + 1}/${requestedYear}`);
        }

        if (!shouldUseCache) {
            this.fastify.log.info('🕒 Cache decision: Generate new report due to time boundary logic');
            return null;
        }

        // If we should use cache, look for existing report
        this.fastify.log.info('🕒 Cache decision: Looking for existing cached report');
        return await this.findExistingReport(userId, startDate, endDate, reportType);
    }

    async findExistingReport(userId, startDate, endDate, reportType) {
        const query = `
            SELECT id, report_data, generation_time_ms, expires_at
            FROM parent_reports
            WHERE user_id = $1
              AND start_date = $2
              AND end_date = $3
              AND report_type = $4
              AND status = 'completed'
              AND expires_at > NOW()
            ORDER BY generated_at DESC
            LIMIT 1
        `;

        const result = await db.query(query, [userId, startDate, endDate, reportType]);
        const report = result.rows[0];

        if (report && report.report_data) {
            // Ensure report_data is properly parsed as JSON if it's stored as text
            if (typeof report.report_data === 'string') {
                try {
                    report.report_data = JSON.parse(report.report_data);
                } catch (e) {
                    this.fastify.log.error('Failed to parse cached report_data JSON:', e.message);
                }
            }
        }

        return report || null;
    }

    async storeReport(reportInfo) {
        const query = `
            INSERT INTO parent_reports (
                user_id, report_type, start_date, end_date, report_data,
                generation_time_ms, ai_analysis_included, status
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, 'completed')
            RETURNING id
        `;

        const values = [
            reportInfo.userId,
            reportInfo.reportType,
            reportInfo.startDate,
            reportInfo.endDate,
            JSON.stringify(reportInfo.reportData),
            reportInfo.generationTimeMs,
            reportInfo.aiAnalysisIncluded
        ];

        const result = await db.query(query, values);
        return result.rows[0].id;
    }

    // REMOVED: storeReportMetrics, storeProgressHistory, updateReportMetrics
    // These functions were removed because migration 005_cleanup_unused_tables dropped:
    // - report_metrics table (use app logging instead)
    // - student_progress_history table (superseded by time-series queries)
    // Migration 005 intentionally removed these tables as unused to simplify the schema by 26%
    // All metrics are now logged to console instead of being stored in the database

    /**
     * Email report to recipients
     */
    async emailReport(request, reply) {
        const startTime = Date.now();

        try {
            const { reportId } = request.params;
            const { to, subject, message } = request.body;

            this.fastify.log.info(`📧 === REPORT EMAIL REQUEST ===`);
            this.fastify.log.info(`🆔 Report ID: ${reportId}`);
            this.fastify.log.info(`📬 Recipients: ${to.join(', ')}`);

            // Get authenticated user ID
            const authenticatedUserId = await this.getUserIdFromToken(request);
            if (!authenticatedUserId) {
                return reply.status(401).send({
                    success: false,
                    error: 'Authentication required to email reports',
                    code: 'AUTHENTICATION_REQUIRED'
                });
            }

            // Get the report data
            const query = `
                SELECT
                    pr.*,
                    u.name as student_name
                FROM parent_reports pr
                JOIN users u ON pr.user_id = u.id
                WHERE pr.id = $1 AND pr.status = 'completed' AND pr.expires_at > NOW()
            `;

            const result = await db.query(query, [reportId]);

            if (result.rows.length === 0) {
                return reply.status(404).send({
                    success: false,
                    error: 'Report not found or expired',
                    code: 'REPORT_NOT_FOUND'
                });
            }

            const report = result.rows[0];

            // Verify user has access to this report
            const hasAccess = await this.verifyStudentAccess(authenticatedUserId, report.user_id);
            if (!hasAccess) {
                return reply.status(403).send({
                    success: false,
                    error: 'Access denied to this report',
                    code: 'ACCESS_DENIED'
                });
            }

            // Generate PDF for email attachment
            this.fastify.log.info(`📄 Generating PDF for email attachment...`);

            const reportData = {
                report: {
                    id: report.id,
                    student_name: report.student_name,
                    report_type: report.report_type,
                    start_date: report.start_date,
                    end_date: report.end_date,
                    generated_at: report.generated_at,
                    ai_analysis_included: report.ai_analysis_included
                },
                report_data: report.report_data
            };

            const pdfPath = await this.exportService.generatePDFReport(reportData);

            // Send email
            this.fastify.log.info(`📧 Sending email to recipients...`);

            const startDate = new Date(report.start_date).toLocaleDateString();
            const endDate = new Date(report.end_date).toLocaleDateString();

            const emailOptions = {
                to: to,
                subject: subject || `StudyAI Progress Report - ${report.student_name}`,
                studentName: report.student_name,
                reportPeriod: `${startDate} - ${endDate}`,
                customMessage: message
            };

            const emailResult = await this.exportService.sendReportByEmail(pdfPath, emailOptions);

            // Clean up temporary file
            const fs = require('fs');
            fs.unlinkSync(pdfPath);

            // Log share action (database storage removed in migration 005)
            this.fastify.log.info(`📊 Report ${reportId} shared via email`);

            const duration = Date.now() - startTime;
            this.fastify.log.info(`✅ === REPORT EMAIL SUCCESS ===`);
            this.fastify.log.info(`⏱️ Total email time: ${duration}ms`);
            this.fastify.log.info(`📧 Message ID: ${emailResult.messageId}`);

            return reply.send({
                success: true,
                message: 'Report emailed successfully',
                recipients: to,
                messageId: emailResult.messageId,
                processing_time_ms: duration
            });

        } catch (error) {
            this.fastify.log.error('❌ === REPORT EMAIL ERROR ===');
            this.fastify.log.error(`Error details: ${error.message}`);
            this.fastify.log.error(`Stack trace: ${error.stack}`);

            return reply.status(500).send({
                success: false,
                error: 'Failed to email report',
                code: 'EMAIL_ERROR',
                details: error.message,
                processing_time_ms: Date.now() - startTime
            });
        }
    }

    /**
     * Generate shareable link for report
     */
    async generateShareLink(request, reply) {
        const startTime = Date.now();

        try {
            const { reportId } = request.params;
            const { expiryDays = 7, maxAccess, password } = request.body;

            this.fastify.log.info(`🔗 === GENERATE SHARE LINK REQUEST ===`);
            this.fastify.log.info(`🆔 Report ID: ${reportId}`);
            this.fastify.log.info(`⏰ Expiry Days: ${expiryDays}`);

            // Get authenticated user ID
            const authenticatedUserId = await this.getUserIdFromToken(request);
            if (!authenticatedUserId) {
                return reply.status(401).send({
                    success: false,
                    error: 'Authentication required to share reports',
                    code: 'AUTHENTICATION_REQUIRED'
                });
            }

            // Verify report exists and user has access
            const query = `
                SELECT pr.*, u.name as student_name
                FROM parent_reports pr
                JOIN users u ON pr.user_id = u.id
                WHERE pr.id = $1 AND pr.status = 'completed' AND pr.expires_at > NOW()
            `;

            const result = await db.query(query, [reportId]);

            if (result.rows.length === 0) {
                return reply.status(404).send({
                    success: false,
                    error: 'Report not found or expired',
                    code: 'REPORT_NOT_FOUND'
                });
            }

            const report = result.rows[0];

            // Verify user has access to this report
            const hasAccess = await this.verifyStudentAccess(authenticatedUserId, report.user_id);
            if (!hasAccess) {
                return reply.status(403).send({
                    success: false,
                    error: 'Access denied to this report',
                    code: 'ACCESS_DENIED'
                });
            }

            // Generate shareable link
            const shareData = await this.exportService.generateShareableLink(reportId, {
                expiryDays,
                maxAccess,
                password
            });

            // Store share record in database (optional - for tracking)
            const shareQuery = `
                INSERT INTO report_shares (
                    report_id, share_id, created_by, expires_at, max_access, password_protected
                ) VALUES ($1, $2, $3, $4, $5, $6)
                ON CONFLICT DO NOTHING
            `;

            await db.query(shareQuery, [
                reportId,
                shareData.shareId,
                authenticatedUserId,
                shareData.expiresAt,
                maxAccess,
                !!password
            ]).catch(() => {
                // Ignore error if table doesn't exist - this is optional functionality
            });

            // Log share action (database storage removed in migration 005)
            this.fastify.log.info(`📊 Report ${reportId} shared via link`);

            const duration = Date.now() - startTime;
            this.fastify.log.info(`✅ === SHARE LINK GENERATED ===`);
            this.fastify.log.info(`⏱️ Generation time: ${duration}ms`);
            this.fastify.log.info(`🔗 Share ID: ${shareData.shareId}`);

            return reply.send({
                success: true,
                shareUrl: shareData.shareUrl,
                shareId: shareData.shareId,
                expiresAt: shareData.expiresAt,
                accessInstructions: shareData.accessInstructions,
                processing_time_ms: duration
            });

        } catch (error) {
            this.fastify.log.error('❌ === SHARE LINK ERROR ===');
            this.fastify.log.error(`Error details: ${error.message}`);
            this.fastify.log.error(`Stack trace: ${error.stack}`);

            return reply.status(500).send({
                success: false,
                error: 'Failed to generate share link',
                code: 'SHARE_LINK_ERROR',
                details: error.message,
                processing_time_ms: Date.now() - startTime
            });
        }
    }

    /**
     * Get human-readable narrative report
     */
    async getNarrative(request, reply) {
        try {
            const { reportId } = request.params;

            this.fastify.log.info(`📝 === GET NARRATIVE REQUEST ===`);
            this.fastify.log.info(`🆔 Report ID: ${reportId}`);

            // Get authenticated user ID
            const authenticatedUserId = await this.getUserIdFromToken(request);
            if (!authenticatedUserId) {
                return reply.status(401).send({
                    success: false,
                    error: 'Authentication required',
                    code: 'AUTHENTICATION_REQUIRED'
                });
            }

            // Get the narrative using the service
            const narrative = await this.narrativeService.getNarrativeByReportId(reportId);

            if (!narrative) {
                this.fastify.log.warn(`❌ No narrative found for report ID: ${reportId}`);
                return reply.status(404).send({
                    success: false,
                    error: 'Narrative not found for this report',
                    code: 'NARRATIVE_NOT_FOUND'
                });
            }

            // Verify user has access to this report by checking the parent report
            const reportQuery = `
                SELECT user_id FROM parent_reports
                WHERE id = $1 AND status = 'completed' AND expires_at > NOW()
            `;
            const reportResult = await db.query(reportQuery, [reportId]);

            if (reportResult.rows.length === 0) {
                return reply.status(404).send({
                    success: false,
                    error: 'Report not found or expired',
                    code: 'REPORT_NOT_FOUND'
                });
            }

            const hasAccess = await this.verifyStudentAccess(authenticatedUserId, reportResult.rows[0].user_id);
            if (!hasAccess) {
                return reply.status(403).send({
                    success: false,
                    error: 'Access denied to this narrative',
                    code: 'ACCESS_DENIED'
                });
            }

            this.fastify.log.info(`✅ Narrative retrieved successfully: ${narrative.id}`);

            const narrativeResponse = {
                success: true,
                narrative: {
                    id: narrative.id,
                    content: narrative.narrative_content,
                    summary: narrative.report_summary,
                    keyInsights: narrative.key_insights || [],
                    recommendations: narrative.recommendations || [],
                    wordCount: narrative.word_count || 0,
                    generatedAt: narrative.generated_at,
                    toneStyle: narrative.tone_style,
                    language: narrative.language,
                    readingLevel: narrative.reading_level
                }
            };

            return reply.send(narrativeResponse);

        } catch (error) {
            this.fastify.log.error('❌ Get narrative error:', error);
            return reply.status(500).send({
                success: false,
                error: 'Failed to retrieve narrative',
                code: 'NARRATIVE_RETRIEVAL_ERROR',
                details: error.message
            });
        }
    }

    /**
     * List narrative reports for a student
     */
    async getStudentNarratives(request, reply) {
        try {
            const { studentId } = request.params;
            const { limit = 10, offset = 0 } = request.query;

            this.fastify.log.info(`📝 === GET STUDENT NARRATIVES REQUEST ===`);
            this.fastify.log.info(`👤 Student ID: ${studentId}`);
            this.fastify.log.info(`📄 Limit: ${limit}, Offset: ${offset}`);

            // Get authenticated user ID
            const authenticatedUserId = await this.getUserIdFromToken(request);
            if (!authenticatedUserId) {
                return reply.status(401).send({
                    success: false,
                    error: 'Authentication required',
                    code: 'AUTHENTICATION_REQUIRED'
                });
            }

            // Verify access
            const hasAccess = await this.verifyStudentAccess(authenticatedUserId, studentId);
            if (!hasAccess) {
                return reply.status(403).send({
                    success: false,
                    error: 'Access denied to student narratives',
                    code: 'ACCESS_DENIED'
                });
            }

            // Get narratives using the service
            const narratives = await this.narrativeService.listUserNarratives(studentId, limit, offset);

            // Get total count for pagination
            const countQuery = `
                SELECT COUNT(*) as total
                FROM parent_report_narratives prn
                JOIN parent_reports pr ON prn.parent_report_id = pr.id
                WHERE pr.user_id = $1 AND pr.status = 'completed'
            `;
            const countResult = await db.query(countQuery, [studentId]);
            const totalNarratives = parseInt(countResult.rows[0].total);

            this.fastify.log.info(`✅ Retrieved ${narratives.length} narratives for student ${studentId}`);
            this.fastify.log.info(`📊 Total narratives: ${totalNarratives}`);

            return reply.send({
                success: true,
                narratives: narratives.map(narrative => ({
                    id: narrative.id,
                    parentReportId: narrative.parent_report_id,
                    summary: narrative.report_summary,
                    wordCount: narrative.word_count,
                    generatedAt: narrative.generated_at,
                    toneStyle: narrative.tone_style,
                    readingLevel: narrative.reading_level,
                    reportType: narrative.report_type,
                    reportPeriod: {
                        startDate: narrative.start_date,
                        endDate: narrative.end_date
                    }
                })),
                pagination: {
                    total: totalNarratives,
                    limit: parseInt(limit),
                    offset: parseInt(offset),
                    hasMore: offset + limit < totalNarratives
                }
            });

        } catch (error) {
            this.fastify.log.error('❌ Get student narratives error:', error);
            return reply.status(500).send({
                success: false,
                error: 'Failed to retrieve student narratives',
                code: 'STUDENT_NARRATIVES_RETRIEVAL_ERROR',
                details: error.message
            });
        }
    }
}

module.exports = ParentReportsRoutes;