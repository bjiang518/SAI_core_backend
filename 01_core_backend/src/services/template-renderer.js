/**
 * Template Renderer Service
 * Manages Handlebars template compilation and rendering for parent reports
 */

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

        try {
            // Register partials
            await this.registerPartials();

            // Register helpers
            this.registerHelpers();

            this.initialized = true;
            console.log('✅ TemplateRenderer initialized');
        } catch (error) {
            console.error('❌ TemplateRenderer initialization failed:', error);
            throw error;
        }
    }

    /**
     * Register Handlebars partials (shared components)
     */
    async registerPartials() {
        try {
            const files = await fs.readdir(this.partialsDir);

            for (const file of files) {
                if (!file.endsWith('.hbs')) continue;

                const partialName = path.basename(file, '.hbs');
                const partialPath = path.join(this.partialsDir, file);
                const partialContent = await fs.readFile(partialPath, 'utf-8');

                Handlebars.registerPartial(partialName, partialContent);
                console.log(`  📝 Registered partial: ${partialName}`);
            }
        } catch (error) {
            console.warn('⚠️ No partials directory found, skipping partial registration');
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
            if (!value) return false;
            if (Array.isArray(value)) return value.length > 0;
            if (typeof value === 'object') return Object.keys(value).length > 0;
            return true;
        });

        // String concatenation
        Handlebars.registerHelper('concat', function(...args) {
            // Remove the last argument (Handlebars options object)
            args.pop();
            return args.join('');
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
