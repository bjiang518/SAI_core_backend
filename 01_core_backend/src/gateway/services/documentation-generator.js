/**
 * API Documentation Generator
 * Generates interactive documentation from OpenAPI specifications
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

class DocumentationGenerator {
  constructor() {
    this.specsDir = path.join(__dirname, '../../docs/api');
    this.outputDir = path.join(__dirname, '../../docs/generated');
    this.templatesDir = path.join(__dirname, '../templates');
    this.baseUrl = process.env.API_BASE_URL || 'http://localhost:3001';
    
    this.ensureDirectories();
  }

  /**
   * Ensure required directories exist
   */
  ensureDirectories() {
    [this.outputDir, this.templatesDir].forEach(dir => {
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
    });
  }

  /**
   * Generate all documentation
   */
  async generateAll() {
    console.log('📚 Generating API Documentation...');
    
    const results = {
      swagger_ui: await this.generateSwaggerUI(),
      redoc: await this.generateReDoc(),
      markdown: await this.generateMarkdown(),
      postman: await this.generatePostmanCollection(),
      client_examples: await this.generateClientExamples()
    };
    
    await this.generateIndex();
    
    console.log('✅ API Documentation generated successfully');
    return results;
  }

  /**
   * Generate Swagger UI documentation
   */
  async generateSwaggerUI() {
    const swaggerHtml = this.getSwaggerUITemplate();
    const outputPath = path.join(this.outputDir, 'swagger-ui.html');
    
    // Load gateway spec for Swagger UI
    const gatewaySpec = this.loadSpec('gateway-spec.yml');
    const specJson = JSON.stringify(gatewaySpec, null, 2);
    
    const html = swaggerHtml
      .replace('{{SPEC_JSON}}', specJson)
      .replace('{{API_TITLE}}', gatewaySpec?.info?.title || 'StudyAI API')
      .replace('{{API_VERSION}}', gatewaySpec?.info?.version || '1.0.0');
    
    fs.writeFileSync(outputPath, html);
    console.log(`📄 Swagger UI generated: ${outputPath}`);
    
    return { path: outputPath, url: `/docs/swagger-ui.html` };
  }

  /**
   * Generate ReDoc documentation
   */
  async generateReDoc() {
    const redocHtml = this.getReDocTemplate();
    const outputPath = path.join(this.outputDir, 'redoc.html');
    
    const gatewaySpec = this.loadSpec('gateway-spec.yml');
    const specJson = JSON.stringify(gatewaySpec, null, 2);
    
    const html = redocHtml
      .replace('{{SPEC_JSON}}', specJson)
      .replace('{{API_TITLE}}', gatewaySpec?.info?.title || 'StudyAI API')
      .replace('{{API_VERSION}}', gatewaySpec?.info?.version || '1.0.0');
    
    fs.writeFileSync(outputPath, html);
    console.log(`📄 ReDoc generated: ${outputPath}`);
    
    return { path: outputPath, url: `/docs/redoc.html` };
  }

  /**
   * Generate Markdown documentation
   */
  async generateMarkdown() {
    const gatewaySpec = this.loadSpec('gateway-spec.yml');
    const aiEngineSpec = this.loadSpec('ai-engine-spec.yml');
    
    const gatewayMd = this.specToMarkdown(gatewaySpec, 'API Gateway');
    const aiEngineMd = this.specToMarkdown(aiEngineSpec, 'AI Engine');
    
    const gatewayPath = path.join(this.outputDir, 'api-gateway.md');
    const aiEnginePath = path.join(this.outputDir, 'ai-engine.md');
    
    fs.writeFileSync(gatewayPath, gatewayMd);
    fs.writeFileSync(aiEnginePath, aiEngineMd);
    
    console.log(`📄 Markdown docs generated: ${gatewayPath}, ${aiEnginePath}`);
    
    return {
      gateway: { path: gatewayPath, url: `/docs/api-gateway.md` },
      aiEngine: { path: aiEnginePath, url: `/docs/ai-engine.md` }
    };
  }

  /**
   * Generate Postman collection
   */
  async generatePostmanCollection() {
    const gatewaySpec = this.loadSpec('gateway-spec.yml');
    const collection = this.specToPostman(gatewaySpec);
    
    const outputPath = path.join(this.outputDir, 'studyai-api.postman_collection.json');
    fs.writeFileSync(outputPath, JSON.stringify(collection, null, 2));
    
    console.log(`📄 Postman collection generated: ${outputPath}`);
    
    return { path: outputPath, url: `/docs/studyai-api.postman_collection.json` };
  }

  /**
   * Generate client examples
   */
  async generateClientExamples() {
    const gatewaySpec = this.loadSpec('gateway-spec.yml');
    const examples = {
      javascript: this.generateJavaScriptExamples(gatewaySpec),
      python: this.generatePythonExamples(gatewaySpec),
      curl: this.generateCurlExamples(gatewaySpec)
    };
    
    Object.entries(examples).forEach(([lang, code]) => {
      const outputPath = path.join(this.outputDir, `client-examples-${lang}.${lang === 'curl' ? 'sh' : lang === 'javascript' ? 'js' : 'py'}`);
      fs.writeFileSync(outputPath, code);
      console.log(`📄 ${lang} examples generated: ${outputPath}`);
    });
    
    return examples;
  }

  /**
   * Generate documentation index
   */
  async generateIndex() {
    const indexHtml = this.getIndexTemplate();
    const outputPath = path.join(this.outputDir, 'index.html');
    
    const gatewaySpec = this.loadSpec('gateway-spec.yml');
    const aiEngineSpec = this.loadSpec('ai-engine-spec.yml');
    
    const html = indexHtml
      .replace('{{API_TITLE}}', 'StudyAI API Documentation')
      .replace('{{API_VERSION}}', gatewaySpec?.info?.version || '1.0.0')
      .replace('{{GATEWAY_ENDPOINTS}}', this.getEndpointCount(gatewaySpec))
      .replace('{{AI_ENGINE_ENDPOINTS}}', this.getEndpointCount(aiEngineSpec))
      .replace('{{GENERATION_DATE}}', new Date().toISOString());
    
    fs.writeFileSync(outputPath, html);
    console.log(`📄 Documentation index generated: ${outputPath}`);
  }

  /**
   * Load OpenAPI specification
   */
  loadSpec(filename) {
    const specPath = path.join(this.specsDir, filename);
    if (!fs.existsSync(specPath)) {
      console.warn(`⚠️ Specification not found: ${filename}`);
      return null;
    }
    
    const content = fs.readFileSync(specPath, 'utf8');
    return yaml.load(content);
  }

  /**
   * Convert OpenAPI spec to Markdown
   */
  specToMarkdown(spec, title) {
    if (!spec) return `# ${title}\n\nSpecification not available.`;
    
    let md = `# ${title}\n\n`;
    
    if (spec.info) {
      md += `**Version:** ${spec.info.version}\\n`;
      md += `**Description:** ${spec.info.description || 'No description available'}\\n\\n`;
    }
    
    if (spec.servers) {
      md += `## Servers\\n\\n`;
      spec.servers.forEach(server => {
        md += `- **${server.description || 'Server'}:** \`${server.url}\`\\n`;
      });
      md += '\\n';
    }
    
    if (spec.paths) {
      md += `## Endpoints\\n\\n`;
      
      Object.entries(spec.paths).forEach(([path, pathItem]) => {
        md += `### ${path}\\n\\n`;
        
        Object.entries(pathItem).forEach(([method, operation]) => {
          if (method === 'parameters') return;
          
          md += `#### ${method.toUpperCase()}\\n\\n`;
          md += `**Summary:** ${operation.summary || 'No summary'}\\n\\n`;
          md += `**Description:** ${operation.description || 'No description'}\\n\\n`;
          
          if (operation.parameters) {
            md += `**Parameters:**\\n\\n`;
            operation.parameters.forEach(param => {
              md += `- \`${param.name}\` (${param.in}) - ${param.description || 'No description'}\\n`;
            });
            md += '\\n';
          }
          
          if (operation.requestBody) {
            md += `**Request Body:** Required\\n\\n`;
          }
          
          if (operation.responses) {
            md += `**Responses:**\\n\\n`;
            Object.entries(operation.responses).forEach(([code, response]) => {
              md += `- **${code}:** ${response.description || 'No description'}\\n`;
            });
            md += '\\n';
          }
        });
      });
    }
    
    return md;
  }

  /**
   * Convert OpenAPI spec to Postman collection
   */
  specToPostman(spec) {
    if (!spec) return null;
    
    const collection = {
      info: {
        name: spec.info?.title || 'API Collection',
        description: spec.info?.description || '',
        version: spec.info?.version || '1.0.0',
        schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json'
      },
      variable: [
        {
          key: 'baseUrl',
          value: this.baseUrl,
          type: 'string'
        }
      ],
      item: []
    };
    
    if (spec.paths) {
      Object.entries(spec.paths).forEach(([path, pathItem]) => {
        Object.entries(pathItem).forEach(([method, operation]) => {
          if (method === 'parameters') return;
          
          const item = {
            name: operation.summary || `${method.toUpperCase()} ${path}`,
            request: {
              method: method.toUpperCase(),
              header: [],
              url: {
                raw: `{{baseUrl}}${path}`,
                host: ['{{baseUrl}}'],
                path: path.split('/').filter(p => p)
              }
            }
          };
          
          // Add request body if exists
          if (operation.requestBody && operation.requestBody.content) {
            const contentType = Object.keys(operation.requestBody.content)[0];
            item.request.header.push({
              key: 'Content-Type',
              value: contentType
            });
            
            if (contentType === 'application/json') {
              const example = operation.requestBody.content[contentType].example;
              if (example) {
                item.request.body = {
                  mode: 'raw',
                  raw: JSON.stringify(example, null, 2)
                };
              }
            }
          }
          
          collection.item.push(item);
        });
      });
    }
    
    return collection;
  }

  /**
   * Generate JavaScript client examples
   */
  generateJavaScriptExamples(spec) {
    let js = `// StudyAI API JavaScript Client Examples\\n`;
    js += `// Base URL: ${this.baseUrl}\\n\\n`;
    
    js += `class StudyAIClient {\\n`;
    js += `  constructor(baseUrl = '${this.baseUrl}') {\\n`;
    js += `    this.baseUrl = baseUrl;\\n`;
    js += `  }\\n\\n`;
    
    js += `  async request(method, path, data = null) {\\n`;
    js += `    const options = {\\n`;
    js += `      method,\\n`;
    js += `      headers: {\\n`;
    js += `        'Content-Type': 'application/json'\\n`;
    js += `      }\\n`;
    js += `    };\\n\\n`;
    js += `    if (data) {\\n`;
    js += `      options.body = JSON.stringify(data);\\n`;
    js += `    }\\n\\n`;
    js += `    const response = await fetch(\`\${this.baseUrl}\${path}\`, options);\\n`;
    js += `    return await response.json();\\n`;
    js += `  }\\n\\n`;
    
    if (spec && spec.paths) {
      Object.entries(spec.paths).forEach(([path, pathItem]) => {
        Object.entries(pathItem).forEach(([method, operation]) => {
          if (method === 'parameters') return;
          
          const methodName = this.pathToMethodName(path, method);
          const hasBody = operation.requestBody;
          
          if (hasBody) {
            const example = operation.requestBody?.content?.['application/json']?.example;
            js += `  async ${methodName}(data) {\\n`;
            js += `    return await this.request('${method.toUpperCase()}', '${path}', data);\\n`;
            js += `  }\\n\\n`;
            
            if (example) {
              js += `  // Example usage:\\n`;
              js += `  // await client.${methodName}(${JSON.stringify(example, null, 2)});\\n\\n`;
            }
          } else {
            js += `  async ${methodName}() {\\n`;
            js += `    return await this.request('${method.toUpperCase()}', '${path}');\\n`;
            js += `  }\\n\\n`;
          }
        });
      });
    }
    
    js += `}\\n\\n`;
    js += `// Usage example:\\n`;
    js += `const client = new StudyAIClient();\\n`;
    js += `client.getHealth().then(console.log);\\n`;
    
    return js;
  }

  /**
   * Generate Python client examples
   */
  generatePythonExamples(spec) {
    let py = `"""StudyAI API Python Client Examples"""\\n`;
    py += `import requests\\n`;
    py += `import json\\n\\n`;
    
    py += `class StudyAIClient:\\n`;
    py += `    def __init__(self, base_url="${this.baseUrl}"):\\n`;
    py += `        self.base_url = base_url\\n\\n`;
    
    py += `    def request(self, method, path, data=None):\\n`;
    py += `        url = f"{self.base_url}{path}"\\n`;
    py += `        headers = {"Content-Type": "application/json"}\\n`;
    py += `        \\n`;
    py += `        if data:\\n`;
    py += `            response = requests.request(method, url, json=data, headers=headers)\\n`;
    py += `        else:\\n`;
    py += `            response = requests.request(method, url, headers=headers)\\n`;
    py += `        \\n`;
    py += `        return response.json()\\n\\n`;
    
    if (spec && spec.paths) {
      Object.entries(spec.paths).forEach(([path, pathItem]) => {
        Object.entries(pathItem).forEach(([method, operation]) => {
          if (method === 'parameters') return;
          
          const methodName = this.pathToMethodName(path, method);
          const hasBody = operation.requestBody;
          
          if (hasBody) {
            py += `    def ${methodName}(self, data):\\n`;
            py += `        return self.request("${method.upper()}", "${path}", data)\\n\\n`;
          } else {
            py += `    def ${methodName}(self):\\n`;
            py += `        return self.request("${method.upper()}", "${path}")\\n\\n`;
          }
        });
      });
    }
    
    py += `# Usage example:\\n`;
    py += `client = StudyAIClient()\\n`;
    py += `print(client.get_health())\\n`;
    
    return py;
  }

  /**
   * Generate cURL examples
   */
  generateCurlExamples(spec) {
    let curl = `#!/bin/bash\\n`;
    curl += `# StudyAI API cURL Examples\\n`;
    curl += `# Base URL: ${this.baseUrl}\\n\\n`;
    
    curl += `BASE_URL="${this.baseUrl}"\\n\\n`;
    
    if (spec && spec.paths) {
      Object.entries(spec.paths).forEach(([path, pathItem]) => {
        Object.entries(pathItem).forEach(([method, operation]) => {
          if (method === 'parameters') return;
          
          curl += `# ${operation.summary || `${method.toUpperCase()} ${path}`}\\n`;
          curl += `curl -X ${method.toUpperCase()} \\\\\\n`;
          curl += `  "\${BASE_URL}${path}" \\\\\\n`;
          curl += `  -H "Content-Type: application/json"`;
          
          if (operation.requestBody?.content?.['application/json']?.example) {
            const example = JSON.stringify(operation.requestBody.content['application/json'].example);
            curl += ` \\\\\\n  -d '${example}'`;
          }
          
          curl += `\\n\\n`;
        });
      });
    }
    
    return curl;
  }

  /**
   * Convert path to method name
   */
  pathToMethodName(path, method) {
    const segments = path.split('/').filter(s => s && !s.startsWith('{'));
    const methodParts = [method.toLowerCase(), ...segments.slice(1)];
    return methodParts.join('_').replace(/-/g, '_');
  }

  /**
   * Get endpoint count from spec
   */
  getEndpointCount(spec) {
    if (!spec || !spec.paths) return 0;
    
    let count = 0;
    Object.values(spec.paths).forEach(pathItem => {
      Object.keys(pathItem).forEach(method => {
        if (method !== 'parameters') count++;
      });
    });
    return count;
  }

  /**
   * Get Swagger UI HTML template
   */
  getSwaggerUITemplate() {
    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>{{API_TITLE}} - Swagger UI</title>
  <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@4.15.5/swagger-ui.css" />
  <style>
    html { box-sizing: border-box; overflow: -moz-scrollbars-vertical; overflow-y: scroll; }
    *, *:before, *:after { box-sizing: inherit; }
    body { margin:0; background: #fafafa; }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@4.15.5/swagger-ui-bundle.js"></script>
  <script src="https://unpkg.com/swagger-ui-dist@4.15.5/swagger-ui-standalone-preset.js"></script>
  <script>
    window.onload = function() {
      const ui = SwaggerUIBundle({
        spec: {{SPEC_JSON}},
        dom_id: '#swagger-ui',
        deepLinking: true,
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIStandalonePreset
        ],
        plugins: [
          SwaggerUIBundle.plugins.DownloadUrl
        ],
        layout: "StandaloneLayout"
      });
    };
  </script>
</body>
</html>`;
  }

  /**
   * Get ReDoc HTML template
   */
  getReDocTemplate() {
    return `<!DOCTYPE html>
<html>
<head>
  <title>{{API_TITLE}} - ReDoc</title>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link href="https://fonts.googleapis.com/css?family=Montserrat:300,400,700|Roboto:300,400,700" rel="stylesheet">
  <style>
    body { margin: 0; padding: 0; }
  </style>
</head>
<body>
  <redoc spec='{{SPEC_JSON}}'></redoc>
  <script src="https://cdn.jsdelivr.net/npm/redoc@2.0.0/bundles/redoc.standalone.js"></script>
</body>
</html>`;
  }

  /**
   * Get documentation index template
   */
  getIndexTemplate() {
    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{API_TITLE}}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 2rem; background: #f8f9fa; }
    .container { max-width: 1200px; margin: 0 auto; background: white; padding: 2rem; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
    h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 1rem; }
    .docs-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 2rem; margin: 2rem 0; }
    .doc-card { background: #f8f9fa; padding: 1.5rem; border-radius: 8px; border-left: 4px solid #3498db; }
    .doc-card h3 { margin-top: 0; color: #2c3e50; }
    .doc-card a { color: #3498db; text-decoration: none; font-weight: 500; }
    .doc-card a:hover { text-decoration: underline; }
    .stats { background: #e8f5e8; padding: 1rem; border-radius: 8px; margin: 2rem 0; }
    .stats h3 { margin-top: 0; color: #27ae60; }
  </style>
</head>
<body>
  <div class="container">
    <h1>{{API_TITLE}}</h1>
    <p>Version: {{API_VERSION}} | Generated: {{GENERATION_DATE}}</p>
    
    <div class="stats">
      <h3>📊 API Statistics</h3>
      <ul>
        <li>Gateway Endpoints: {{GATEWAY_ENDPOINTS}}</li>
        <li>AI Engine Endpoints: {{AI_ENGINE_ENDPOINTS}}</li>
        <li>Total Endpoints: {{GATEWAY_ENDPOINTS}} + {{AI_ENGINE_ENDPOINTS}}</li>
      </ul>
    </div>

    <div class="docs-grid">
      <div class="doc-card">
        <h3>🔧 Interactive Documentation</h3>
        <p>Explore and test the API endpoints interactively</p>
        <a href="swagger-ui.html">Swagger UI →</a><br>
        <a href="redoc.html">ReDoc →</a>
      </div>

      <div class="doc-card">
        <h3>📖 Markdown Documentation</h3>
        <p>Detailed API documentation in Markdown format</p>
        <a href="api-gateway.md">API Gateway Docs →</a><br>
        <a href="ai-engine.md">AI Engine Docs →</a>
      </div>

      <div class="doc-card">
        <h3>📮 Testing Collections</h3>
        <p>Import into your favorite API testing tool</p>
        <a href="studyai-api.postman_collection.json">Postman Collection →</a>
      </div>

      <div class="doc-card">
        <h3>💻 Client Examples</h3>
        <p>Code examples for different programming languages</p>
        <a href="client-examples-javascript.js">JavaScript →</a><br>
        <a href="client-examples-python.py">Python →</a><br>
        <a href="client-examples-curl.sh">cURL →</a>
      </div>
    </div>
  </div>
</body>
</html>`;
  }
}

// Documentation server for serving generated docs
class DocumentationServer {
  constructor(docsPath) {
    this.docsPath = docsPath || path.join(__dirname, '../../docs/generated');
  }

  /**
   * Get Fastify plugin for serving documentation
   */
  getFastifyPlugin() {
    return async (fastify) => {
      // Serve static documentation files
      fastify.register(require('@fastify/static'), {
        root: this.docsPath,
        prefix: '/docs/',
        decorateReply: false
      });

      // Documentation index redirect
      fastify.get('/docs', async (request, reply) => {
        return reply.redirect('/docs/index.html');
      });

      // API specification endpoints
      fastify.get('/api/openapi.json', async (request, reply) => {
        const specPath = path.join(__dirname, '../../docs/api/gateway-spec.yml');
        if (fs.existsSync(specPath)) {
          const spec = yaml.load(fs.readFileSync(specPath, 'utf8'));
          return reply.send(spec);
        }
        return reply.code(404).send({ error: 'OpenAPI specification not found' });
      });

      fastify.get('/api/openapi.yml', async (request, reply) => {
        const specPath = path.join(__dirname, '../../docs/api/gateway-spec.yml');
        if (fs.existsSync(specPath)) {
          const content = fs.readFileSync(specPath, 'utf8');
          return reply.type('text/yaml').send(content);
        }
        return reply.code(404).send({ error: 'OpenAPI specification not found' });
      });

      console.log('📚 Documentation server enabled at /docs');
    };
  }
}

// Export everything
const documentationGenerator = new DocumentationGenerator();

module.exports = {
  DocumentationGenerator,
  DocumentationServer,
  documentationGenerator
};