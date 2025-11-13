#!/usr/bin/env node

/**
 * Initialize OpenAI Assistants
 *
 * Creates all assistants and stores their IDs in the database
 * Run this script once before enabling Assistants API
 *
 * Usage: node scripts/initialize-assistants.js
 */

require('dotenv').config();
const { createPracticeGeneratorAssistant } = require('../src/services/assistants/practice-generator-assistant');
const { db } = require('../src/utils/railway-database');

async function initializeAssistants() {
  console.log('🚀 Initializing OpenAI Assistants...\n');

  try {
    // Ensure database connection
    await db.query('SELECT 1');
    console.log('✅ Database connected\n');

    // 1. Create Practice Generator Assistant
    console.log('📝 Step 1: Creating Practice Generator Assistant...');
    const practiceGenerator = await createPracticeGeneratorAssistant();
    console.log(`✅ Assistant ID: ${practiceGenerator.assistant_id}\n`);

    // Update .env file reminder
    console.log('📋 IMPORTANT: Update your .env file with the following:');
    console.log('─'.repeat(60));
    console.log(`PRACTICE_GENERATOR_ASSISTANT_ID=${practiceGenerator.assistant_id}`);
    console.log('─'.repeat(60));
    console.log('');

    // TODO: Create other assistants when ready
    console.log('ℹ️  Other assistants (Homework Tutor, Image Analyzer, etc.) will be created in future phases\n');

    console.log('✅ Initialization complete!');
    console.log('');
    console.log('Next steps:');
    console.log('1. Copy the assistant ID above to your .env file');
    console.log('2. Set USE_ASSISTANTS_API=false initially (for testing)');
    console.log('3. Run tests: npm test');
    console.log('4. Gradually enable: Set ASSISTANTS_ROLLOUT_PERCENTAGE=10 (10% of users)');
    console.log('5. Monitor metrics and gradually increase to 100%');

    process.exit(0);
  } catch (error) {
    console.error('❌ Initialization failed:', error);
    console.error('');
    console.error('Troubleshooting:');
    console.error('- Ensure OPENAI_API_KEY is set in .env');
    console.error('- Ensure database migrations have been run');
    console.error('- Check database connection');
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  initializeAssistants();
}

module.exports = { initializeAssistants };
