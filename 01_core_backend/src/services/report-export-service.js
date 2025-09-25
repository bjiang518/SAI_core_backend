/**
 * StudyAI Report Export Service
 * Handles PDF generation, image exports, and sharing functionality
 */

const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs').promises;
const path = require('path');

class ReportExportService {
    constructor() {
        this.exportDir = path.join(process.cwd(), 'temp/exports');
        this.ensureExportDirectory();

        // Email transporter setup (will be configured based on environment)
        this.emailTransporter = null;
        this.initializeEmailService();
    }

    async ensureExportDirectory() {
        try {
            await fs.mkdir(this.exportDir, { recursive: true });
        } catch (error) {
            console.error('Error creating export directory:', error);
        }
    }

    initializeEmailService() {
        // Configure email service based on environment variables
        if (process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS) {
            this.emailTransporter = nodemailer.createTransporter({
                host: process.env.SMTP_HOST,
                port: process.env.SMTP_PORT || 587,
                secure: process.env.SMTP_SECURE === 'true',
                auth: {
                    user: process.env.SMTP_USER,
                    pass: process.env.SMTP_PASS
                }
            });
        } else {
            console.log('📧 Email service not configured - SMTP credentials missing');
        }
    }

    /**
     * Generate PDF report from report data
     * @param {Object} reportData - Complete report data
     * @param {Object} options - Export options
     * @returns {Promise<String>} Path to generated PDF file
     */
    async generatePDFReport(reportData, options = {}) {
        const reportId = reportData.report?.id || uuidv4();
        const fileName = `parent-report-${reportId}-${Date.now()}.pdf`;
        const filePath = path.join(this.exportDir, fileName);

        return new Promise((resolve, reject) => {
            try {
                const doc = new PDFDocument({
                    margin: 50,
                    size: 'A4',
                    info: {
                        Title: `StudyAI Parent Report - ${reportData.report?.student_name || 'Student'}`,
                        Author: 'StudyAI',
                        Subject: 'Academic Progress Report',
                        Keywords: 'education, progress, academic, report'
                    }
                });

                const stream = require('fs').createWriteStream(filePath);
                doc.pipe(stream);

                // Generate PDF content
                this.generatePDFContent(doc, reportData, options);

                doc.end();

                stream.on('finish', () => {
                    resolve(filePath);
                });

                stream.on('error', (error) => {
                    reject(error);
                });

            } catch (error) {
                reject(error);
            }
        });
    }

    /**
     * Generate the actual PDF content
     */
    generatePDFContent(doc, reportData, options) {
        const report = reportData.report_data || reportData.report;
        const studentName = reportData.report?.student_name || 'Student';

        // Header
        this.addPDFHeader(doc, studentName, report);

        // Academic Performance Section
        if (report.academic) {
            this.addAcademicSection(doc, report.academic);
        }

        // Activity Metrics Section
        if (report.activity) {
            this.addActivitySection(doc, report.activity);
        }

        // Subject Breakdown
        if (report.subjects) {
            this.addSubjectsSection(doc, report.subjects);
        }

        // Progress Comparison
        if (report.progress) {
            this.addProgressSection(doc, report.progress);
        }

        // Mental Health & Wellbeing
        if (report.mentalHealth) {
            this.addMentalHealthSection(doc, report.mentalHealth);
        }

        // Mistakes Analysis
        if (report.mistakes) {
            this.addMistakesSection(doc, report.mistakes);
        }

        // AI Insights
        if (report.aiInsights) {
            this.addAIInsightsSection(doc, report.aiInsights);
        }

        // Footer
        this.addPDFFooter(doc, report);
    }

    addPDFHeader(doc, studentName, report) {
        // StudyAI Logo and Title
        doc.fontSize(24)
           .fillColor('#2563eb')
           .text('StudyAI', 50, 50)
           .fontSize(18)
           .fillColor('#1f2937')
           .text('Academic Progress Report', 50, 80);

        // Student Name and Report Period
        doc.fontSize(16)
           .fillColor('#374151')
           .text(`Student: ${studentName}`, 50, 120);

        if (report.reportPeriod) {
            const startDate = new Date(report.reportPeriod.startDate).toLocaleDateString();
            const endDate = new Date(report.reportPeriod.endDate).toLocaleDateString();
            doc.text(`Report Period: ${startDate} - ${endDate}`, 50, 145);
        }

        if (report.generatedAt) {
            const generatedDate = new Date(report.generatedAt).toLocaleString();
            doc.text(`Generated: ${generatedDate}`, 50, 170);
        }

        // Separator line
        doc.moveTo(50, 200)
           .lineTo(545, 200)
           .strokeColor('#e5e7eb')
           .stroke();

        doc.y = 220;
    }

    addAcademicSection(doc, academic) {
        this.addSectionHeader(doc, 'Academic Performance');

        // Key metrics in columns
        const leftCol = 50;
        const rightCol = 300;
        let currentY = doc.y + 10;

        doc.fontSize(12)
           .fillColor('#374151')
           .text(`Overall Accuracy: ${(academic.overallAccuracy * 100).toFixed(1)}%`, leftCol, currentY)
           .text(`Questions Answered: ${academic.totalQuestions}`, rightCol, currentY);

        currentY += 20;
        doc.text(`Average Confidence: ${(academic.averageConfidence * 100).toFixed(1)}%`, leftCol, currentY)
           .text(`Correct Answers: ${academic.correctAnswers}`, rightCol, currentY);

        currentY += 20;
        doc.text(`Study Time: ${academic.timeSpentMinutes} minutes`, leftCol, currentY)
           .text(`Questions per Day: ${academic.questionsPerDay}`, rightCol, currentY);

        // Improvement trend
        currentY += 30;
        doc.fontSize(11)
           .fillColor('#6b7280')
           .text(`Improvement Trend: ${this.formatTrend(academic.improvementTrend)}`, leftCol, currentY);

        doc.y = currentY + 30;
    }

    addActivitySection(doc, activity) {
        this.addSectionHeader(doc, 'Learning Activity');

        const leftCol = 50;
        const rightCol = 300;
        let currentY = doc.y + 10;

        // Study Time metrics
        if (activity.studyTime) {
            doc.fontSize(12)
               .fillColor('#374151')
               .text(`Total Study Time: ${activity.studyTime.totalMinutes} minutes`, leftCol, currentY)
               .text(`Active Days: ${activity.studyTime.activeDays}`, rightCol, currentY);

            currentY += 20;
            doc.text(`Avg Session Length: ${activity.studyTime.averageSessionMinutes} min`, leftCol, currentY)
               .text(`Sessions per Day: ${activity.studyTime.sessionsPerDay}`, rightCol, currentY);
        }

        // Engagement metrics
        if (activity.engagement) {
            currentY += 30;
            doc.fontSize(11)
               .fillColor('#6b7280')
               .text('Engagement Metrics:', leftCol, currentY);

            currentY += 15;
            doc.text(`Total Conversations: ${activity.engagement.totalConversations}`, leftCol, currentY)
               .text(`Messages Exchanged: ${activity.engagement.totalMessages}`, rightCol, currentY);
        }

        doc.y = currentY + 30;
    }

    addSubjectsSection(doc, subjects) {
        this.addSectionHeader(doc, 'Subject Performance');

        let currentY = doc.y + 10;
        const subjects_list = Object.keys(subjects);

        subjects_list.forEach((subject, index) => {
            if (currentY > 700) { // Add new page if needed
                doc.addPage();
                currentY = 50;
                this.addSectionHeader(doc, 'Subject Performance (continued)');
                currentY = doc.y + 10;
            }

            const data = subjects[subject];

            doc.fontSize(13)
               .fillColor('#1f2937')
               .text(subject.charAt(0).toUpperCase() + subject.slice(1), 50, currentY);

            currentY += 20;

            if (data.performance) {
                doc.fontSize(11)
                   .fillColor('#374151')
                   .text(`Accuracy: ${(data.performance.accuracy * 100).toFixed(1)}%`, 70, currentY)
                   .text(`Questions: ${data.performance.totalQuestions}`, 200, currentY)
                   .text(`Correct: ${data.performance.correctAnswers}`, 320, currentY);
            }

            if (data.activity) {
                currentY += 15;
                doc.text(`Study Time: ${data.activity.totalStudyTime} min`, 70, currentY)
                   .text(`Sessions: ${data.activity.totalSessions}`, 200, currentY);
            }

            currentY += 25;
        });

        doc.y = currentY + 10;
    }

    addProgressSection(doc, progress) {
        this.addSectionHeader(doc, 'Progress Analysis');

        let currentY = doc.y + 10;

        // Overall trend
        doc.fontSize(12)
           .fillColor('#374151')
           .text(`Overall Trend: ${this.formatTrend(progress.overallTrend)}`, 50, currentY);

        currentY += 25;

        // Improvements
        if (progress.improvements && progress.improvements.length > 0) {
            doc.fontSize(11)
               .fillColor('#059669')
               .text('✓ Improvements:', 50, currentY);

            currentY += 15;
            progress.improvements.forEach(improvement => {
                if (currentY > 720) {
                    doc.addPage();
                    currentY = 50;
                }
                doc.fontSize(10)
                   .text(`• ${improvement.message}`, 70, currentY);
                currentY += 12;
            });
        }

        // Concerns
        if (progress.concerns && progress.concerns.length > 0) {
            currentY += 10;
            doc.fontSize(11)
               .fillColor('#dc2626')
               .text('⚠ Areas for Attention:', 50, currentY);

            currentY += 15;
            progress.concerns.forEach(concern => {
                if (currentY > 720) {
                    doc.addPage();
                    currentY = 50;
                }
                doc.fontSize(10)
                   .text(`• ${concern.message}`, 70, currentY);
                currentY += 12;
            });
        }

        // Recommendations
        if (progress.recommendations && progress.recommendations.length > 0) {
            currentY += 15;
            doc.fontSize(11)
               .fillColor('#2563eb')
               .text('💡 Recommendations:', 50, currentY);

            currentY += 15;
            progress.recommendations.forEach(rec => {
                if (currentY > 700) {
                    doc.addPage();
                    currentY = 50;
                }
                doc.fontSize(10)
                   .fillColor('#374151')
                   .text(`• ${rec.title}: ${rec.description}`, 70, currentY);
                currentY += 12;
            });
        }

        doc.y = currentY + 20;
    }

    addMentalHealthSection(doc, mentalHealth) {
        this.addSectionHeader(doc, 'Wellbeing & Engagement');

        let currentY = doc.y + 10;

        // Overall wellbeing score
        const wellbeingPercentage = (mentalHealth.overallWellbeing * 100).toFixed(1);
        doc.fontSize(12)
           .fillColor('#374151')
           .text(`Overall Wellbeing Score: ${wellbeingPercentage}%`, 50, currentY);

        // Alerts if any
        if (mentalHealth.alerts && mentalHealth.alerts.length > 0) {
            currentY += 25;
            doc.fontSize(11)
               .fillColor('#dc2626')
               .text('⚠ Wellbeing Alerts:', 50, currentY);

            currentY += 15;
            mentalHealth.alerts.forEach(alert => {
                doc.fontSize(10)
                   .text(`• ${alert.message}`, 70, currentY);
                currentY += 12;
            });
        }

        doc.y = currentY + 20;
    }

    addMistakesSection(doc, mistakes) {
        if (mistakes.totalMistakes === 0) return;

        this.addSectionHeader(doc, 'Mistake Analysis');

        let currentY = doc.y + 10;

        doc.fontSize(12)
           .fillColor('#374151')
           .text(`Total Mistakes: ${mistakes.totalMistakes}`, 50, currentY)
           .text(`Mistake Rate: ${mistakes.mistakeRate}%`, 300, currentY);

        // Top mistake patterns
        if (mistakes.patterns && mistakes.patterns.length > 0) {
            currentY += 25;
            doc.fontSize(11)
               .fillColor('#6b7280')
               .text('Most Common Mistake Areas:', 50, currentY);

            currentY += 15;
            mistakes.patterns.slice(0, 3).forEach(pattern => {
                doc.fontSize(10)
                   .fillColor('#374151')
                   .text(`• ${pattern.subject}: ${pattern.count} mistakes (${pattern.percentage}%)`, 70, currentY);
                currentY += 12;
            });
        }

        // Recommendations
        if (mistakes.recommendations && mistakes.recommendations.length > 0) {
            currentY += 15;
            doc.fontSize(11)
               .fillColor('#2563eb')
               .text('Recommendations:', 50, currentY);

            currentY += 15;
            mistakes.recommendations.forEach(rec => {
                doc.fontSize(10)
                   .fillColor('#374151')
                   .text(`• ${rec}`, 70, currentY);
                currentY += 12;
            });
        }

        doc.y = currentY + 20;
    }

    addAIInsightsSection(doc, aiInsights) {
        if (!aiInsights || typeof aiInsights !== 'object') return;

        this.addSectionHeader(doc, 'AI-Powered Insights');

        let currentY = doc.y + 10;

        // Learning Patterns
        if (aiInsights.learningPatterns) {
            doc.fontSize(11)
               .fillColor('#6b7280')
               .text('Learning Patterns:', 50, currentY);

            currentY += 15;
            if (aiInsights.learningPatterns.recommendation) {
                doc.fontSize(10)
                   .fillColor('#374151')
                   .text(`• ${aiInsights.learningPatterns.recommendation}`, 70, currentY);
                currentY += 12;
            }
        }

        // Predictive Analytics
        if (aiInsights.predictiveAnalytics) {
            currentY += 10;
            doc.fontSize(11)
               .fillColor('#6b7280')
               .text('Performance Predictions:', 50, currentY);

            currentY += 15;
            if (aiInsights.predictiveAnalytics.recommendation) {
                doc.fontSize(10)
                   .fillColor('#374151')
                   .text(`• ${aiInsights.predictiveAnalytics.recommendation}`, 70, currentY);
                currentY += 12;
            }
        }

        // Risk Assessment
        if (aiInsights.riskAssessment) {
            currentY += 10;
            doc.fontSize(11)
               .fillColor('#6b7280')
               .text('Risk Assessment:', 50, currentY);

            currentY += 15;
            if (aiInsights.riskAssessment.recommendation) {
                doc.fontSize(10)
                   .fillColor('#374151')
                   .text(`• ${aiInsights.riskAssessment.recommendation}`, 70, currentY);
                currentY += 12;
            }
        }

        doc.y = currentY + 20;
    }

    addSectionHeader(doc, title) {
        doc.fontSize(14)
           .fillColor('#1f2937')
           .text(title, 50, doc.y);

        // Underline
        doc.moveTo(50, doc.y + 5)
           .lineTo(200, doc.y + 5)
           .strokeColor('#e5e7eb')
           .stroke();

        doc.y += 20;
    }

    addPDFFooter(doc, report) {
        // Add footer to last page
        const pageHeight = doc.page.height;

        doc.fontSize(8)
           .fillColor('#9ca3af')
           .text('Generated by StudyAI - Personalized Learning Assistant', 50, pageHeight - 50)
           .text(`Report ID: ${report.metadata?.reportId || 'N/A'}`, 50, pageHeight - 35)
           .text(`studyai.app`, 450, pageHeight - 35);
    }

    formatTrend(trend) {
        const trendMap = {
            'improving': '📈 Improving',
            'stable': '➡️ Stable',
            'declining': '📉 Needs Attention',
            'excellent_progress': '🚀 Excellent Progress',
            'needs_attention': '⚠️ Needs Attention',
            'insufficient_data': '📊 More Data Needed'
        };
        return trendMap[trend] || trend;
    }

    /**
     * Send report via email
     * @param {String} reportPath - Path to the PDF report
     * @param {Object} emailOptions - Email configuration
     * @returns {Promise<Object>} Email send result
     */
    async sendReportByEmail(reportPath, emailOptions) {
        if (!this.emailTransporter) {
            throw new Error('Email service not configured');
        }

        const { to, subject, studentName, reportPeriod } = emailOptions;

        const mailOptions = {
            from: process.env.SMTP_FROM || process.env.SMTP_USER,
            to: to,
            subject: subject || `StudyAI Progress Report - ${studentName}`,
            html: `
                <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
                    <h2 style="color: #2563eb;">StudyAI Progress Report</h2>
                    <p>Dear Parent/Guardian,</p>
                    <p>Please find attached the detailed progress report for <strong>${studentName}</strong>.</p>
                    <p><strong>Report Period:</strong> ${reportPeriod}</p>
                    <p>This comprehensive report includes:</p>
                    <ul>
                        <li>Academic performance metrics</li>
                        <li>Learning activity analysis</li>
                        <li>Subject-wise breakdown</li>
                        <li>Progress comparison with previous periods</li>
                        <li>Mental health and wellbeing indicators</li>
                        <li>AI-powered insights and recommendations</li>
                    </ul>
                    <p>If you have any questions about this report, please don't hesitate to contact us.</p>
                    <p>Best regards,<br>The StudyAI Team</p>
                    <hr style="margin: 20px 0; border: none; border-top: 1px solid #e5e7eb;">
                    <p style="font-size: 12px; color: #6b7280;">
                        This is an automated message from StudyAI. Please do not reply to this email.
                    </p>
                </div>
            `,
            attachments: [
                {
                    filename: path.basename(reportPath),
                    path: reportPath,
                    contentType: 'application/pdf'
                }
            ]
        };

        try {
            const result = await this.emailTransporter.sendMail(mailOptions);
            console.log('📧 Report sent successfully:', result.messageId);
            return { success: true, messageId: result.messageId };
        } catch (error) {
            console.error('📧 Email send error:', error);
            throw error;
        }
    }

    /**
     * Generate shareable link for report
     * @param {String} reportId - Report ID
     * @param {Object} options - Link options
     * @returns {Object} Share link details
     */
    async generateShareableLink(reportId, options = {}) {
        const shareId = uuidv4();
        const expiresAt = new Date();
        expiresAt.setDate(expiresAt.getDate() + (options.expiryDays || 7));

        // In a real implementation, you'd store this in the database
        const shareLink = {
            shareId: shareId,
            reportId: reportId,
            expiresAt: expiresAt,
            accessCount: 0,
            maxAccess: options.maxAccess || null,
            password: options.password || null,
            createdAt: new Date()
        };

        const baseUrl = process.env.FRONTEND_URL || 'https://studyai.app';
        const shareUrl = `${baseUrl}/shared-report/${shareId}`;

        return {
            success: true,
            shareUrl: shareUrl,
            shareId: shareId,
            expiresAt: expiresAt,
            accessInstructions: 'Share this link with authorized recipients. The link will expire automatically.'
        };
    }

    /**
     * Clean up temporary export files
     * @param {Number} olderThanHours - Clean files older than X hours
     */
    async cleanupTempFiles(olderThanHours = 24) {
        try {
            const files = await fs.readdir(this.exportDir);
            const now = Date.now();
            let deletedCount = 0;

            for (const file of files) {
                const filePath = path.join(this.exportDir, file);
                const stats = await fs.stat(filePath);
                const fileAge = now - stats.mtime.getTime();
                const maxAge = olderThanHours * 60 * 60 * 1000;

                if (fileAge > maxAge) {
                    await fs.unlink(filePath);
                    deletedCount++;
                }
            }

            console.log(`🧹 Cleaned up ${deletedCount} temporary export files`);
            return { cleaned: deletedCount };
        } catch (error) {
            console.error('Error cleaning temp files:', error);
            return { error: error.message };
        }
    }
}

module.exports = ReportExportService;