# Template-Based Parent Reports Implementation Plan

**Created**: 2026-02-05
**Status**: Ready for Implementation
**Goal**: Convert to stable template-based architecture with automated Sunday night generation

---

## Table of Contents
1. [Overview](#overview)
2. [Architecture Changes](#architecture-changes)
3. [Phase-by-Phase Implementation](#phase-by-phase-implementation)
4. [File Structure](#file-structure)
5. [Automated Scheduling](#automated-scheduling)
6. [Testing Strategy](#testing-strategy)
7. [Rollout Plan](#rollout-plan)

---

## Overview

### Current State
- ❌ HTML generated inline in JS files
- ❌ AI generates full HTML (unstable)
- ❌ Manual generation only (no automation)
- ❌ Missing Activity and Improvement reports
- ✅ Mental Health report functional
- ✅ Behavior signals available

### Target State
- ✅ Fixed HTML templates (Handlebars)
- ✅ AI provides structured JSON data only
- ✅ Automated Sunday night generation per user timezone
- ✅ Manual generation kept for testing
- ✅ All 4 reports: Activity, Improvement, Mental Health, Summary
- ✅ Graceful handling of missing data

---

## Architecture Changes

### Before: AI Generates Full HTML
```javascript
// mental-health-report-generator.js
generateMentalHealthHTML(analysis) {
  const html = `
    <!DOCTYPE html>
    <html>
      <body>
        <p>${analysis.summary}</p>  // AI content mixed with HTML
      </body>
    </html>
  `;
  return html;
}
```

### After: Template + Structured Data
```javascript
// mental-health-report-generator.js
async generateReport(userId, startDate, endDate) {
  // 1. Fetch raw data
  const rawData = await this.fetchReportData(userId, startDate, endDate);

  // 2. AI analyzes and returns JSON
  const structuredData = await this.analyzeData(rawData);

  // 3. Template engine renders
  const html = await templateRenderer.render('mental-health', structuredData);

  return html;
}
```

**Key Principle**: AI generates content (JSON), never HTML structure.

---

## Phase-by-Phase Implementation

### Phase 1: Template Infrastructure (Days 1-2)

#### Step 1.1: Install Dependencies
```bash
cd 01_core_backend
npm install handlebars node-cron node-schedule
```

**Packages**:
- `handlebars` - Template engine
- `node-cron` - Automated scheduling
- `node-schedule` - Advanced scheduling with timezone support

---

#### Step 1.2: Create Directory Structure
```bash
mkdir -p src/templates/reports
mkdir -p src/templates/reports/partials
mkdir -p src/templates/styles
mkdir -p src/services/report-generators
mkdir -p src/services/scheduling
```

**New Directory Tree**:
```
01_core_backend/src/
├── templates/
│   ├── reports/
│   │   ├── mental-health.hbs       ← Mental Health Report
│   │   ├── activity.hbs            ← Activity Report
│   │   ├── improvement.hbs         ← Areas of Improvement
│   │   ├── summary.hbs             ← Summary Report
│   │   └── partials/
│   │       ├── header.hbs          ← Shared header
│   │       ├── footer.hbs          ← Shared footer
│   │       ├── timeline.hbs        ← Emotional timeline
│   │       ├── alert.hbs           ← Red flag alerts
│   │       └── metrics-card.hbs    ← Metric display card
│   └── styles/
│       └── report-styles.css       ← Shared CSS for all reports
├── services/
│   ├── report-generators/
│   │   ├── mental-health-report-generator.js  ← Updated
│   │   ├── activity-report-generator.js       ← NEW
│   │   ├── improvement-report-generator.js    ← NEW
│   │   └── summary-report-generator.js        ← Updated
│   ├── template-renderer.js        ← NEW: Template engine wrapper
│   └── scheduling/
│       ├── report-scheduler.js     ← NEW: Cron job manager
│       └── timezone-manager.js     ← NEW: User timezone handler
```

---

#### Step 1.3: Implement Template Renderer

**File**: `src/services/template-renderer.js`

```javascript
const Handlebars = require('handlebars');
const fs = require('fs').promises;
const path = require('path');

class TemplateRenderer {
    constructor() {
        this.templatesDir = path.join(__dirname, '../templates/reports');
        this.partialsDir = path.join(__dirname, '../templates/reports/partials');
        this.stylesDir = path.join(__dirname, '../templates/styles');
        this.compiledTemplates = new Map();
        this.initialized = false;
    }

    /**
     * Initialize: Load templates and partials
     */
    async initialize() {
        if (this.initialized) return;

        console.log('🎨 Initializing TemplateRenderer...');

        // Register partials
        await this.registerPartials();

        // Register helpers
        this.registerHelpers();

        this.initialized = true;
        console.log('✅ TemplateRenderer initialized');
    }

    /**
     * Register Handlebars partials (shared components)
     */
    async registerPartials() {
        const files = await fs.readdir(this.partialsDir);

        for (const file of files) {
            if (!file.endsWith('.hbs')) continue;

            const partialName = path.basename(file, '.hbs');
            const partialPath = path.join(this.partialsDir, file);
            const partialContent = await fs.readFile(partialPath, 'utf-8');

            Handlebars.registerPartial(partialName, partialContent);
            console.log(`  📝 Registered partial: ${partialName}`);
        }
    }

    /**
     * Register custom Handlebars helpers
     */
    registerHelpers() {
        // Date formatting
        Handlebars.registerHelper('formatDate', function(date) {
            if (!date) return 'N/A';
            return new Date(date).toLocaleDateString('en-US', {
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            });
        });

        // Status icon
        Handlebars.registerHelper('statusIcon', function(status) {
            const icons = {
                'excellent': '✅',
                'good': '✅',
                'moderate': '⚠️',
                'poor': '❌',
                'none': '⚪'
            };
            return icons[status?.toLowerCase()] || '⚪';
        });

        // Percentage formatting
        Handlebars.registerHelper('percent', function(value) {
            if (value === null || value === undefined) return 'N/A';
            return (value * 100).toFixed(1) + '%';
        });

        // Default value if null/undefined
        Handlebars.registerHelper('default', function(value, defaultValue) {
            return value !== null && value !== undefined ? value : defaultValue;
        });

        // Math operations
        Handlebars.registerHelper('multiply', function(a, b) {
            return a * b;
        });

        Handlebars.registerHelper('round', function(value, decimals = 1) {
            if (value === null || value === undefined) return 'N/A';
            return Number(value).toFixed(decimals);
        });

        // Comparison operators
        Handlebars.registerHelper('gt', function(a, b) {
            return a > b;
        });

        Handlebars.registerHelper('gte', function(a, b) {
            return a >= b;
        });

        Handlebars.registerHelper('lt', function(a, b) {
            return a < b;
        });

        Handlebars.registerHelper('eq', function(a, b) {
            return a === b;
        });

        // Array/object checks
        Handlebars.registerHelper('isEmpty', function(value) {
            if (!value) return true;
            if (Array.isArray(value)) return value.length === 0;
            if (typeof value === 'object') return Object.keys(value).length === 0;
            return false;
        });

        Handlebars.registerHelper('isNotEmpty', function(value) {
            return !Handlebars.helpers.isEmpty(value);
        });

        console.log('  🔧 Registered Handlebars helpers');
    }

    /**
     * Render a template with data
     * @param {string} templateName - Template file (without .hbs)
     * @param {Object} data - Data to populate template
     * @returns {Promise<string>} Rendered HTML
     */
    async render(templateName, data) {
        await this.initialize();

        try {
            // Load and compile template (with caching)
            if (!this.compiledTemplates.has(templateName)) {
                const templatePath = path.join(this.templatesDir, `${templateName}.hbs`);
                const templateContent = await fs.readFile(templatePath, 'utf-8');
                const compiled = Handlebars.compile(templateContent, {
                    strict: false // Allow undefined variables
                });
                this.compiledTemplates.set(templateName, compiled);
                console.log(`  📄 Compiled template: ${templateName}`);
            }

            const template = this.compiledTemplates.get(templateName);

            // Load CSS
            const css = await this.loadCSS();

            // Enrich data with global properties
            const enrichedData = {
                ...data,
                generatedAt: new Date().toISOString(),
                generatedAtFormatted: new Date().toLocaleString('en-US', {
                    year: 'numeric',
                    month: 'long',
                    day: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit'
                }),
                inlineCSS: css, // Inline CSS for iOS WKWebView
                appVersion: process.env.APP_VERSION || '1.0.0'
            };

            // Render
            const html = template(enrichedData);
            console.log(`  ✅ Rendered template: ${templateName} (${html.length} chars)`);

            return html;

        } catch (error) {
            console.error(`❌ Template rendering failed: ${templateName}`, error);
            throw new Error(`Template rendering failed: ${error.message}`);
        }
    }

    /**
     * Load CSS for inline injection
     */
    async loadCSS() {
        try {
            const cssPath = path.join(this.stylesDir, 'report-styles.css');
            return await fs.readFile(cssPath, 'utf-8');
        } catch (error) {
            console.warn('⚠️ CSS file not found, using empty styles');
            return '';
        }
    }

    /**
     * Clear template cache (useful for development)
     */
    clearCache() {
        this.compiledTemplates.clear();
        this.initialized = false;
        console.log('🗑️ Template cache cleared');
    }
}

// Singleton instance
module.exports = new TemplateRenderer();
```

---

#### Step 1.4: Create Shared CSS

**File**: `src/templates/styles/report-styles.css`

```css
/* StudyAI Parent Reports - Shared Styles */

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
    background: #f8f9fa;
    padding: 16px;
    line-height: 1.6;
    color: #1a1a1a;
    font-size: 16px;
}

.container {
    max-width: 900px;
    margin: 0 auto;
    background: white;
    border-radius: 12px;
    overflow: hidden;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
}

/* Header */
.header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 32px 24px;
    text-align: center;
}

.header h1 {
    font-size: 28px;
    font-weight: 700;
    margin-bottom: 8px;
}

.header .subtitle {
    font-size: 16px;
    opacity: 0.9;
}

/* Sections */
.section {
    padding: 24px;
    border-bottom: 1px solid #e5e7eb;
}

.section:last-child {
    border-bottom: none;
}

.section h2 {
    font-size: 22px;
    font-weight: 600;
    margin-bottom: 16px;
    color: #1a1a1a;
}

.section h3 {
    font-size: 18px;
    font-weight: 600;
    margin-top: 16px;
    margin-bottom: 12px;
    color: #374151;
}

/* Alerts */
.alert {
    padding: 16px;
    border-radius: 8px;
    margin: 16px 24px;
    border-left: 4px solid;
}

.alert-success {
    background: #d1fae5;
    border-color: #10b981;
    color: #065f46;
}

.alert-warning {
    background: #fef3c7;
    border-color: #f59e0b;
    color: #92400e;
}

.alert-danger {
    background: #fee2e2;
    border-color: #ef4444;
    color: #991b1b;
}

.alert-info {
    background: #dbeafe;
    border-color: #3b82f6;
    color: #1e40af;
}

.alert h2 {
    font-size: 20px;
    margin-bottom: 8px;
}

/* Metrics Cards */
.metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 16px;
    margin: 16px 0;
}

.metric-card {
    background: #f9fafb;
    padding: 16px;
    border-radius: 8px;
    text-align: center;
    border: 1px solid #e5e7eb;
}

.metric-card .value {
    font-size: 32px;
    font-weight: 700;
    color: #667eea;
    margin: 8px 0;
}

.metric-card .label {
    font-size: 14px;
    color: #6b7280;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

/* Grade Display */
.grade {
    font-size: 64px;
    font-weight: 700;
    color: #667eea;
    text-align: center;
    margin: 16px 0;
}

/* Timeline */
.timeline {
    border-left: 3px solid #667eea;
    padding-left: 24px;
    margin-left: 12px;
    margin-top: 16px;
}

.timeline-item {
    margin-bottom: 20px;
    position: relative;
}

.timeline-item::before {
    content: '';
    position: absolute;
    left: -27px;
    top: 6px;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: #667eea;
    border: 3px solid white;
    box-shadow: 0 0 0 2px #667eea;
}

.timeline-item strong {
    display: block;
    margin-bottom: 4px;
    color: #1a1a1a;
}

.timeline-item em {
    display: block;
    margin-top: 4px;
    font-size: 14px;
    color: #6b7280;
}

/* Lists */
ul, ol {
    margin-left: 24px;
    margin-top: 12px;
}

li {
    margin-bottom: 8px;
}

/* No Data Message */
.no-data {
    color: #9ca3af;
    font-style: italic;
    text-align: center;
    padding: 24px;
    background: #f9fafb;
    border-radius: 8px;
}

/* Progress Bar */
.progress-bar {
    width: 100%;
    height: 8px;
    background: #e5e7eb;
    border-radius: 4px;
    overflow: hidden;
    margin: 8px 0;
}

.progress-bar-fill {
    height: 100%;
    background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
    border-radius: 4px;
    transition: width 0.3s ease;
}

/* Footer */
.footer {
    background: #f9fafb;
    padding: 16px 24px;
    text-align: center;
    font-size: 14px;
    color: #6b7280;
    border-top: 1px solid #e5e7eb;
}

.footer a {
    color: #667eea;
    text-decoration: none;
}

/* Responsive */
@media (max-width: 640px) {
    body {
        padding: 8px;
    }

    .header {
        padding: 24px 16px;
    }

    .header h1 {
        font-size: 24px;
    }

    .section {
        padding: 16px;
    }

    .metrics-grid {
        grid-template-columns: 1fr;
    }

    .grade {
        font-size: 48px;
    }
}
```

---

### Phase 2: Template Creation (Days 3-4)

#### Template 2.1: Shared Partials

**File**: `src/templates/reports/partials/header.hbs`

```handlebars
<div class="header">
    <h1>{{reportTitle}}</h1>
    <div class="subtitle">
        {{studentName}} |
        {{formatDate reportPeriod.start}} - {{formatDate reportPeriod.end}}
    </div>
</div>
```

**File**: `src/templates/reports/partials/footer.hbs`

```handlebars
<div class="footer">
    <p>Generated on {{generatedAtFormatted}}</p>
    <p>StudyAI Parent Reports v{{appVersion}}</p>
    <p><a href="https://studyai.app/help/reports">Learn more about reports</a></p>
</div>
```

**File**: `src/templates/reports/partials/alert.hbs`

```handlebars
<div class="alert alert-{{severity}}">
    <h2>{{icon}} {{title}}</h2>
    <p>{{message}}</p>
    {{#if action}}
    <p><strong>Recommended Action:</strong> {{action}}</p>
    {{/if}}
</div>
```

**File**: `src/templates/reports/partials/metrics-card.hbs`

```handlebars
<div class="metric-card">
    <div class="label">{{label}}</div>
    <div class="value">{{value}}</div>
    {{#if sublabel}}
    <div class="sublabel">{{sublabel}}</div>
    {{/if}}
</div>
```

**File**: `src/templates/reports/partials/timeline.hbs`

```handlebars
<div class="timeline">
    {{#each items}}
    <div class="timeline-item">
        <strong>{{this.date}}</strong>
        <div>{{this.visual}} {{this.description}}</div>
        {{#if this.note}}
        <em>Note: {{this.note}}</em>
        {{/if}}
    </div>
    {{/each}}
</div>
```

---

#### Template 2.2: Mental Health Report

**File**: `src/templates/reports/mental-health.hbs`

```handlebars
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Mental Health Report - {{studentName}}</title>
    <style>{{{inlineCSS}}}</style>
</head>
<body>
    <div class="container">
        {{> header
            reportTitle="Mental Health & Wellbeing Report"
            studentName=studentName
            reportPeriod=reportPeriod
        }}

        <!-- Red Flag Alerts -->
        {{#if hasRedFlags}}
        <div class="alert alert-danger">
            <h2>🚨 Concerns Detected</h2>
            {{#each redFlagAlerts}}
            <div style="margin-top: 12px;">
                <strong>{{this.type}}</strong>: {{this.message}}
                <br><em>Date: {{formatDate this.date}}</em>
                {{#if this.suggestedAction}}
                <br><strong>Action:</strong> {{this.suggestedAction}}
                {{/if}}
            </div>
            {{/each}}
        </div>
        {{else}}
        <div class="alert alert-success">
            <h2>✅ No Concerns Detected</h2>
            <p>Great news! No concerning patterns detected during this period.
            {{studentName}} is showing healthy engagement and emotional balance.</p>
        </div>
        {{/if}}

        <!-- Engagement Quality -->
        <div class="section">
            <h2>💪 Engagement Quality</h2>

            {{#if engagementScore}}
            <div class="grade">{{engagementGrade}}</div>
            <p style="text-align: center;"><strong>Overall Score:</strong> {{engagementScore}}/1.0</p>

            <h3>Breakdown:</h3>
            <ul>
                <li>
                    {{statusIcon curiosityStatus}}
                    <strong>Curiosity:</strong>
                    {{default curiosityLabel "No data"}}
                    {{#if curiosityPercent}}({{curiosityPercent}}% of sessions){{/if}}
                </li>
                <li>
                    {{statusIcon persistenceStatus}}
                    <strong>Persistence:</strong>
                    {{default persistenceLabel "No data"}}
                    {{#if persistencePercent}}({{persistencePercent}}% of sessions){{/if}}
                </li>
                <li>
                    {{statusIcon followUpStatus}}
                    <strong>Follow-up Depth:</strong>
                    {{default followUpLabel "No data"}}
                    {{#if followUpDepth}}({{followUpDepth}}/5){{/if}}
                </li>
            </ul>

            {{#if recommendations}}
            <p><strong>💡 Recommendation:</strong> {{recommendations}}</p>
            {{/if}}
            {{else}}
            <p class="no-data">No engagement data available for this period.</p>
            {{/if}}
        </div>

        <!-- Emotional Wellbeing Timeline -->
        <div class="section">
            <h2>🎭 Emotional Wellbeing Timeline</h2>
            {{#if emotionalTimeline}}
            {{> timeline items=emotionalTimeline}}
            <p style="margin-top: 16px;"><strong>📊 Trend:</strong> {{emotionalTrend}}</p>
            {{else}}
            <p class="no-data">No emotional timeline data available for this period.</p>
            {{/if}}
        </div>

        <!-- Positive Learning Patterns -->
        {{#if hasPositivePatterns}}
        <div class="section" style="background: #f0fdf4;">
            <h2>🎯 Positive Learning Patterns</h2>
            <ul>
                {{#if ahaMoments}}
                <li>⚡ <strong>{{ahaMoments}} Aha Moments</strong> in past 2 weeks - Making connections!</li>
                {{/if}}
                {{#if curiosityIndicators}}
                <li>🔍 <strong>{{curiosityIndicators}} Curiosity Indicators</strong> - High engagement with material</li>
                {{/if}}
                {{#if persistenceSessions}}
                <li>💪 <strong>{{persistenceSessions.high}}/{{persistenceSessions.total}} sessions</strong> showed high persistence</li>
                {{/if}}
            </ul>
        </div>
        {{/if}}

        <!-- Parent Actions -->
        <div class="section">
            <h2>📋 Suggested Actions for Parents</h2>
            {{#if parentActions}}
            <ol>
                {{#each parentActions}}
                <li><strong>{{this.title}}:</strong> {{this.description}}</li>
                {{/each}}
            </ol>
            {{else}}
            <p class="no-data">No specific actions recommended at this time. Continue current approach!</p>
            {{/if}}
        </div>

        {{> footer generatedAtFormatted=generatedAtFormatted appVersion=appVersion}}
    </div>
</body>
</html>
```

---

#### Template 2.3: Activity Report

**File**: `src/templates/reports/activity.hbs`

```handlebars
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Activity Report - {{studentName}}</title>
    <style>{{{inlineCSS}}}</style>
</head>
<body>
    <div class="container">
        {{> header
            reportTitle="📊 Student Activity Report"
            studentName=studentName
            reportPeriod=reportPeriod
        }}

        <!-- Key Metrics -->
        <div class="section">
            <h2>This Week's Activity</h2>
            <div class="metrics-grid">
                {{> metrics-card
                    label="Questions"
                    value=(default totalQuestions 0)
                    sublabel=(default weekOverWeekChange.questionsText "")
                }}
                {{> metrics-card
                    label="Chat Sessions"
                    value=(default totalChats 0)
                }}
                {{> metrics-card
                    label="Active Days"
                    value=(default activeDays 0)
                    sublabel=(concat "out of " totalDays)
                }}
                {{> metrics-card
                    label="Study Time"
                    value=(default estimatedMinutes 0)
                    sublabel="minutes"
                }}
            </div>
        </div>

        <!-- Subject Breakdown -->
        <div class="section">
            <h2>Subject Distribution</h2>
            {{#if subjects}}
            <table style="width: 100%; border-collapse: collapse; margin-top: 16px;">
                <thead>
                    <tr style="background: #f9fafb; border-bottom: 2px solid #e5e7eb;">
                        <th style="padding: 12px; text-align: left;">Subject</th>
                        <th style="padding: 12px; text-align: center;">Questions</th>
                        <th style="padding: 12px; text-align: center;">Accuracy</th>
                        <th style="padding: 12px; text-align: center;">Homework</th>
                    </tr>
                </thead>
                <tbody>
                    {{#each subjects}}
                    <tr style="border-bottom: 1px solid #e5e7eb;">
                        <td style="padding: 12px;"><strong>{{this.name}}</strong></td>
                        <td style="padding: 12px; text-align: center;">{{this.count}}</td>
                        <td style="padding: 12px; text-align: center;">{{percent this.accuracy}}</td>
                        <td style="padding: 12px; text-align: center;">{{this.homeworkCount}}</td>
                    </tr>
                    {{/each}}
                </tbody>
            </table>
            {{else}}
            <p class="no-data">No subject data available for this period.</p>
            {{/if}}
        </div>

        <!-- Chat Activity -->
        {{#if chatsBySubject}}
        <div class="section">
            <h2>Chat Sessions by Subject</h2>
            <ul>
                {{#each chatsBySubject}}
                <li><strong>{{@key}}:</strong> {{this}} sessions</li>
                {{/each}}
            </ul>
        </div>
        {{/if}}

        <!-- Week-over-Week Comparison -->
        {{#if weekOverWeekChange}}
        <div class="section">
            <h2>📈 Week-over-Week Trend</h2>
            <ul>
                {{#if weekOverWeekChange.questionsChange}}
                <li>
                    Questions:
                    {{#if (gt weekOverWeekChange.questionsChange 0)}}
                    ⬆️ +{{weekOverWeekChange.questionsChange}} from last week
                    {{else if (lt weekOverWeekChange.questionsChange 0)}}
                    ⬇️ {{weekOverWeekChange.questionsChange}} from last week
                    {{else}}
                    ➡️ Same as last week
                    {{/if}}
                </li>
                {{/if}}
                {{#if weekOverWeekChange.accuracyChange}}
                <li>
                    Accuracy:
                    {{#if (gt weekOverWeekChange.accuracyChange 0)}}
                    ⬆️ +{{round weekOverWeekChange.accuracyChange 1}}% improvement
                    {{else if (lt weekOverWeekChange.accuracyChange 0)}}
                    ⬇️ {{round weekOverWeekChange.accuracyChange 1}}% decline
                    {{else}}
                    ➡️ Stable
                    {{/if}}
                </li>
                {{/if}}
                {{#if weekOverWeekChange.engagementTrend}}
                <li>Overall Engagement: {{weekOverWeekChange.engagementTrend}}</li>
                {{/if}}
            </ul>
        </div>
        {{/if}}

        <!-- Summary -->
        <div class="section">
            <h2>Summary</h2>
            {{#if summary}}
            <p>{{summary}}</p>
            {{else}}
            <p>{{studentName}} completed {{default totalQuestions 0}} questions across
            {{default activeDays 0}} active days this week.</p>
            {{/if}}
        </div>

        {{> footer generatedAtFormatted=generatedAtFormatted appVersion=appVersion}}
    </div>
</body>
</html>
```

---

#### Template 2.4: Areas of Improvement Report

**File**: `src/templates/reports/improvement.hbs`

```handlebars
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Areas of Improvement - {{studentName}}</title>
    <style>{{{inlineCSS}}}</style>
</head>
<body>
    <div class="container">
        {{> header
            reportTitle="🎯 Areas for Improvement"
            studentName=studentName
            reportPeriod=reportPeriod
        }}

        {{#if hasImprovements}}
        {{#each subjectImprovements}}
        <div class="section">
            <h2>{{this.subject}}</h2>

            <!-- Current Performance -->
            <div style="background: #f9fafb; padding: 16px; border-radius: 8px; margin: 16px 0;">
                <p><strong>Current Accuracy:</strong> {{percent this.accuracy}}</p>
                {{#if this.accuracyLastWeek}}
                <p><strong>Last Week:</strong> {{percent this.accuracyLastWeek}}</p>
                <p><strong>Change:</strong>
                    {{#if (gt this.change 0)}}
                    ⬆️ +{{percent this.change}} ({{this.trend}})
                    {{else if (lt this.change 0)}}
                    ⬇️ {{percent this.change}} ({{this.trend}})
                    {{else}}
                    ➡️ No change
                    {{/if}}
                </p>
                {{/if}}
                <p><strong>Total Errors:</strong> {{this.totalErrors}}</p>
            </div>

            <!-- Error Breakdown -->
            {{#if this.errorTypes}}
            <h3>Error Patterns</h3>
            {{#each this.errorTypes}}
            <div style="margin: 16px 0; padding: 12px; background: #fef3c7; border-left: 4px solid #f59e0b; border-radius: 4px;">
                <p><strong>{{this.typeName}}</strong> ({{this.count}} instances
                {{#if this.lastWeekCount}}
                , {{#if (gt this.change 0)}}+{{this.change}}{{else}}{{this.change}}{{/if}} from last week
                {{/if}}
                )</p>

                {{#if this.examples}}
                <p style="margin-top: 8px;"><em>Examples:</em></p>
                <ul style="margin-top: 4px;">
                    {{#each this.examples}}
                    <li>{{this}}</li>
                    {{/each}}
                </ul>
                {{/if}}

                {{#if this.suggestion}}
                <p style="margin-top: 8px;"><strong>How to help:</strong> {{this.suggestion}}</p>
                {{/if}}
            </div>
            {{/each}}
            {{/if}}

            <!-- Parent Action -->
            {{#if this.parentAction}}
            <div style="background: #dbeafe; padding: 16px; border-radius: 8px; margin-top: 16px;">
                <p><strong>🎯 Specific Action:</strong> {{this.parentAction}}</p>
            </div>
            {{/if}}
        </div>
        {{/each}}
        {{else}}
        <div class="section">
            <div class="alert alert-success">
                <h2>🎉 Great Work!</h2>
                <p>No major areas of concern detected. {{studentName}} is performing well across all subjects!</p>
            </div>
        </div>
        {{/if}}

        {{> footer generatedAtFormatted=generatedAtFormatted appVersion=appVersion}}
    </div>
</body>
</html>
```

---

#### Template 2.5: Summary Report

**File**: `src/templates/reports/summary.hbs`

```handlebars
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Weekly Summary - {{studentName}}</title>
    <style>{{{inlineCSS}}}</style>
</head>
<body>
    <div class="container">
        {{> header
            reportTitle="📋 Weekly Summary"
            studentName=studentName
            reportPeriod=reportPeriod
        }}

        <!-- Executive Summary -->
        <div class="section">
            <h2>Executive Summary</h2>
            {{#if executiveSummary}}
            <p style="font-size: 18px; line-height: 1.8;">{{executiveSummary}}</p>
            {{else}}
            <p class="no-data">No summary available for this period.</p>
            {{/if}}
        </div>

        <!-- Key Highlights -->
        {{#if highlights}}
        <div class="section" style="background: #f0fdf4;">
            <h2>✨ This Week's Highlights</h2>
            <ul>
                {{#each highlights}}
                <li>{{this}}</li>
                {{/each}}
            </ul>
        </div>
        {{/if}}

        <!-- Areas of Focus -->
        {{#if areasOfFocus}}
        <div class="section" style="background: #fef3c7;">
            <h2>🎯 Areas Needing Attention</h2>
            <ul>
                {{#each areasOfFocus}}
                <li>{{this}}</li>
                {{/each}}
            </ul>
        </div>
        {{/if}}

        <!-- Action Items -->
        <div class="section">
            <h2>📋 Action Items for Parents</h2>
            {{#if actionItems}}
            <ol style="font-size: 17px; line-height: 2;">
                {{#each actionItems}}
                <li><strong>{{this.title}}:</strong> {{this.description}}</li>
                {{/each}}
            </ol>
            {{else}}
            <p class="no-data">No specific actions needed. Keep up the great work!</p>
            {{/if}}
        </div>

        <!-- Celebration -->
        {{#if celebration}}
        <div class="section" style="background: linear-gradient(135deg, #fef3c7 0%, #fed7aa 100%); text-align: center;">
            <h2 style="font-size: 28px;">🌟 Celebration</h2>
            <p style="font-size: 20px; margin-top: 16px;">{{celebration}}</p>
        </div>
        {{/if}}

        {{> footer generatedAtFormatted=generatedAtFormatted appVersion=appVersion}}
    </div>
</body>
</html>
```

---

### Phase 3: Report Generator Services (Days 5-7)

Due to length constraints, I'll outline the structure for each generator:

#### Service 3.1: Activity Report Generator

**File**: `src/services/report-generators/activity-report-generator.js`

```javascript
const templateRenderer = require('../template-renderer');
const { db } = require('../../utils/railway-database');

class ActivityReportGenerator {
    /**
     * Generate activity report
     */
    async generateReport(userId, startDate, endDate) {
        // 1. Fetch raw data
        const questions = await this.fetchQuestions(userId, startDate, endDate);
        const conversations = await this.fetchConversations(userId, startDate, endDate);
        const previousWeekData = await this.fetchPreviousWeekData(userId, startDate);

        // 2. Calculate metrics
        const metrics = this.calculateMetrics(questions, conversations, previousWeekData);

        // 3. Prepare template data
        const templateData = this.prepareTemplateData(userId, startDate, endDate, metrics);

        // 4. Render template
        const html = await templateRenderer.render('activity', templateData);

        return html;
    }

    async fetchQuestions(userId, startDate, endDate) {
        const query = `
            SELECT
                id,
                subject,
                grade,
                archived_at,
                has_visual_elements
            FROM questions
            WHERE user_id = $1
              AND archived_at BETWEEN $2 AND $3
            ORDER BY archived_at ASC
        `;
        const result = await db.query(query, [userId, startDate, endDate]);
        return result.rows;
    }

    // ... implement other methods
}

module.exports = new ActivityReportGenerator();
```

---

### Phase 4: Automated Scheduling (Days 8-9)

#### Service 4.1: Timezone Manager

**File**: `src/services/scheduling/timezone-manager.js`

```javascript
const { db } = require('../../utils/railway-database');

class TimezoneManager {
    /**
     * Get user's local timezone
     */
    async getUserTimezone(userId) {
        const query = `
            SELECT timezone
            FROM profiles
            WHERE user_id = $1
        `;
        const result = await db.query(query, [userId]);

        // Default to UTC if not set
        return result.rows[0]?.timezone || 'UTC';
    }

    /**
     * Get all users who should receive report at current time
     * Returns users where it's Sunday 9 PM in their local timezone
     */
    async getUsersForReportGeneration() {
        const query = `
            SELECT
                u.id as user_id,
                u.email,
                p.timezone,
                p.report_day_of_week,
                p.report_time_hour
            FROM users u
            JOIN profiles p ON u.id = p.user_id
            WHERE p.parent_reports_enabled = true
              AND EXTRACT(DOW FROM NOW() AT TIME ZONE COALESCE(p.timezone, 'UTC')) = COALESCE(p.report_day_of_week, 0)
              AND EXTRACT(HOUR FROM NOW() AT TIME ZONE COALESCE(p.timezone, 'UTC')) = COALESCE(p.report_time_hour, 21)
        `;

        const result = await db.query(query);
        return result.rows;
    }

    /**
     * Calculate next Sunday 9 PM for a user
     */
    getNextReportTime(timezone) {
        const now = new Date();
        const userTime = new Date(now.toLocaleString('en-US', { timeZone: timezone }));

        // Find next Sunday
        const daysUntilSunday = (7 - userTime.getDay()) % 7 || 7;
        const nextSunday = new Date(userTime);
        nextSunday.setDate(userTime.getDate() + daysUntilSunday);
        nextSunday.setHours(21, 0, 0, 0); // 9 PM

        return nextSunday;
    }
}

module.exports = new TimezoneManager();
```

---

#### Service 4.2: Report Scheduler

**File**: `src/services/scheduling/report-scheduler.js`

```javascript
const cron = require('node-cron');
const timezoneManager = require('./timezone-manager');
const parentReportService = require('../parent-report-service');
const logger = require('../../utils/logger');

class ReportScheduler {
    constructor() {
        this.cronJob = null;
        this.isRunning = false;
    }

    /**
     * Start automated report generation
     * Runs every hour to check if any users need reports
     */
    start() {
        if (this.isRunning) {
            logger.warn('⚠️ Report scheduler already running');
            return;
        }

        logger.info('🕐 Starting automated report scheduler...');

        // Run every hour
        this.cronJob = cron.schedule('0 * * * *', async () => {
            await this.generateScheduledReports();
        }, {
            timezone: 'UTC'
        });

        this.isRunning = true;
        logger.info('✅ Report scheduler started');
    }

    /**
     * Stop scheduler
     */
    stop() {
        if (this.cronJob) {
            this.cronJob.stop();
            this.isRunning = false;
            logger.info('🛑 Report scheduler stopped');
        }
    }

    /**
     * Generate reports for users whose local time is Sunday 9 PM
     */
    async generateScheduledReports() {
        try {
            logger.info('📊 Checking for scheduled reports...');

            // Get users who should receive reports now
            const users = await timezoneManager.getUsersForReportGeneration();

            if (users.length === 0) {
                logger.info('  No users scheduled for reports at this time');
                return;
            }

            logger.info(`  📤 Generating reports for ${users.length} users`);

            // Generate reports for each user
            const results = await Promise.allSettled(
                users.map(user => this.generateReportForUser(user))
            );

            // Log results
            const successful = results.filter(r => r.status === 'fulfilled').length;
            const failed = results.filter(r => r.status === 'rejected').length;

            logger.info(`  ✅ Generated ${successful} reports successfully`);
            if (failed > 0) {
                logger.warn(`  ⚠️ Failed to generate ${failed} reports`);
            }

        } catch (error) {
            logger.error('❌ Scheduled report generation failed:', error);
        }
    }

    /**
     * Generate report for a single user
     */
    async generateReportForUser(user) {
        const { user_id, email, timezone } = user;

        try {
            logger.info(`  📝 Generating report for user ${user_id} (${email})`);

            // Calculate date range (past 7 days)
            const endDate = new Date();
            const startDate = new Date();
            startDate.setDate(endDate.getDate() - 7);

            // Generate report
            const result = await parentReportService.generateFullReport(
                user_id,
                startDate,
                endDate,
                {
                    reportType: 'weekly',
                    automated: true,
                    timezone: timezone
                }
            );

            logger.info(`  ✅ Report generated for user ${user_id}: ${result.reportId}`);

            // Optionally: Send email notification
            // await emailService.sendReportNotification(email, result.reportId);

            return result;

        } catch (error) {
            logger.error(`  ❌ Failed to generate report for user ${user_id}:`, error);
            throw error;
        }
    }

    /**
     * Manual trigger for testing
     */
    async generateReportNow(userId) {
        const user = {
            user_id: userId,
            email: 'test@example.com',
            timezone: await timezoneManager.getUserTimezone(userId)
        };

        return await this.generateReportForUser(user);
    }
}

module.exports = new ReportScheduler();
```

---

### Phase 5: Database Schema Updates (Day 10)

#### Migration 5.1: Add Timezone and Scheduling Columns

**File**: `src/migrations/20260205_report_scheduling.sql`

```sql
-- Add report scheduling preferences to profiles table

ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS parent_reports_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS report_day_of_week INTEGER DEFAULT 0, -- 0 = Sunday, 6 = Saturday
ADD COLUMN IF NOT EXISTS report_time_hour INTEGER DEFAULT 21,  -- 21 = 9 PM
ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'UTC';

-- Add index for scheduled report queries
CREATE INDEX IF NOT EXISTS idx_profiles_report_schedule
ON profiles(parent_reports_enabled, report_day_of_week, report_time_hour)
WHERE parent_reports_enabled = true;

-- Add comment
COMMENT ON COLUMN profiles.report_day_of_week IS 'Day of week for automated reports (0=Sunday, 6=Saturday)';
COMMENT ON COLUMN profiles.report_time_hour IS 'Hour of day for automated reports (0-23, in user local time)';
COMMENT ON COLUMN profiles.timezone IS 'User timezone (e.g., America/New_York, UTC)';
```

---

### Phase 6: Integration with Parent Report Service (Day 11)

#### Update parent-reports.js routes

**File**: `src/gateway/routes/parent-reports.js` (add new endpoint)

```javascript
// Manual generation endpoint (for testing)
fastify.post('/api/parent-reports/generate-manual', {
    schema: {
        body: {
            type: 'object',
            required: ['userId'],
            properties: {
                userId: { type: 'string', format: 'uuid' },
                days: { type: 'integer', default: 7 }
            }
        }
    }
}, async (request, reply) => {
    const { userId, days } = request.body;

    try {
        const endDate = new Date();
        const startDate = new Date();
        startDate.setDate(endDate.getDate() - days);

        // Generate all 4 reports
        const result = await parentReportService.generateFullReport(
            userId,
            startDate,
            endDate,
            {
                reportType: 'weekly',
                automated: false,
                manualTrigger: true
            }
        );

        return {
            success: true,
            data: result
        };

    } catch (error) {
        fastify.log.error('Manual report generation failed:', error);
        return reply.status(500).send({
            success: false,
            error: 'Report generation failed'
        });
    }
});
```

---

### Phase 7: Server Initialization (Day 12)

#### Update server.js to start scheduler

**File**: `src/gateway/index.js` (add to startup)

```javascript
const reportScheduler = require('./services/scheduling/report-scheduler');

// Start server
fastify.listen({ port: PORT, host: '0.0.0.0' }, async (err, address) => {
    if (err) {
        fastify.log.error(err);
        process.exit(1);
    }

    fastify.log.info(`🚀 Server listening at ${address}`);

    // Start automated report scheduler
    if (process.env.NODE_ENV === 'production') {
        reportScheduler.start();
        fastify.log.info('✅ Automated report scheduler started');
    } else {
        fastify.log.info('⚠️ Automated scheduler disabled (development mode)');
    }
});

// Graceful shutdown
process.on('SIGTERM', () => {
    fastify.log.info('SIGTERM received, shutting down gracefully...');
    reportScheduler.stop();
    fastify.close(() => {
        process.exit(0);
    });
});
```

---

## Testing Strategy

### Unit Tests

**File**: `tests/template-renderer.test.js`

```javascript
const test = require('tap').test;
const templateRenderer = require('../src/services/template-renderer');

test('TemplateRenderer - renders mental-health template', async (t) => {
    const data = {
        studentName: 'Test Student',
        reportPeriod: {
            start: '2026-01-01',
            end: '2026-01-07'
        },
        hasRedFlags: false,
        engagementScore: 0.85,
        engagementGrade: 'A-'
    };

    const html = await templateRenderer.render('mental-health', data);

    t.ok(html.includes('Test Student'), 'Contains student name');
    t.ok(html.includes('A-'), 'Contains engagement grade');
    t.ok(html.includes('No Concerns Detected'), 'Shows no red flags');
});
```

### Integration Tests

Test manual generation endpoint:
```bash
curl -X POST http://localhost:3000/api/parent-reports/generate-manual \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "USER_UUID_HERE",
    "days": 7
  }'
```

---

## Rollout Plan

### Week 1: Template Infrastructure
- Day 1-2: Implement TemplateRenderer + CSS
- Day 3-4: Create all 4 report templates
- Day 5: Test template rendering

### Week 2: Report Generators
- Day 6: Migrate Mental Health generator
- Day 7: Implement Activity generator
- Day 8: Implement Improvement generator
- Day 9: Implement Summary generator

### Week 3: Automation + Testing
- Day 10: Implement timezone manager
- Day 11: Implement report scheduler
- Day 12: Integration testing
- Day 13-14: End-to-end testing with real data

### Week 4: Production Rollout
- Day 15: Deploy to staging
- Day 16: QA testing
- Day 17: Deploy to production (scheduler disabled)
- Day 18: Monitor manual reports
- Day 19: Enable automated scheduler
- Day 20: Monitor automated generation

---

## Success Criteria

- [ ] All 4 report templates render correctly
- [ ] Missing data displays gracefully (no broken reports)
- [ ] Manual generation works via API
- [ ] Automated Sunday night generation works
- [ ] Reports generated in user's local timezone
- [ ] HTML displays correctly in iOS WKWebView
- [ ] Performance: <5 seconds per report
- [ ] No HTML injection vulnerabilities

---

## Next Steps

1. **Create Phase 1 files** (template infrastructure)
2. **Test template rendering** with sample data
3. **Create all 4 templates** following examples above
4. **Implement report generators** one by one
5. **Add automated scheduling** with timezone support
6. **Integration testing** with real user data
7. **Deploy to production** with manual trigger first
8. **Enable automation** after validation

---

*Document created: 2026-02-05*
*Status: Ready for implementation*
*Estimated time: 3-4 weeks*
