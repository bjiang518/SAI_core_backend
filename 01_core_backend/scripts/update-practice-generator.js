#!/usr/bin/env node

/**
 * Update Practice Generator Assistant Instructions
 *
 * Updates the existing Practice Generator assistant with new instructions
 * without creating a new assistant (preserves assistant ID)
 *
 * Usage: node scripts/update-practice-generator.js
 */

require('dotenv').config();
const { PRACTICE_GENERATOR_INSTRUCTIONS } = require('../src/services/assistants/practice-generator-assistant');
const { assistantsService } = require('../src/services/openai-assistants-service');
const { db } = require('../src/utils/railway-database');

async function updatePracticeGenerator() {
  console.log('🔄 Updating Practice Generator Assistant instructions...\n');

  try {
    // Ensure database connection
    await db.query('SELECT 1');
    console.log('✅ Database connected\n');

    // Get current assistant ID from database
    console.log('📋 Fetching current assistant ID from database...');
    const result = await db.query(`
      SELECT openai_assistant_id
      FROM assistants_config
      WHERE purpose = 'practice_generator' AND is_active = true
      LIMIT 1
    `);

    if (result.rows.length === 0) {
      console.error('❌ No active Practice Generator assistant found in database');
      console.error('   Run: node scripts/initialize-assistants.js first');
      process.exit(1);
    }

    const assistantId = result.rows[0].openai_assistant_id;
    console.log(`✅ Found assistant ID: ${assistantId}\n`);

    // Update assistant instructions via OpenAI API
    console.log('🔧 Updating assistant instructions...');
    const updatedAssistant = await assistantsService.client.beta.assistants.update(
      assistantId,
      {
        instructions: PRACTICE_GENERATOR_INSTRUCTIONS,
        metadata: {
          version: "1.1.0",
          last_updated: new Date().toISOString(),
          update_reason: "Fixed JSON output formatting and made function calls optional"
        }
      }
    );

    console.log(`✅ Assistant updated successfully!\n`);
    console.log('Updated properties:');
    console.log(`  - Name: ${updatedAssistant.name}`);
    console.log(`  - Model: ${updatedAssistant.model}`);
    console.log(`  - Instructions length: ${PRACTICE_GENERATOR_INSTRUCTIONS.length} characters`);
    console.log(`  - Version: 1.1.0\n`);

    // Update database metadata
    await db.query(`
      UPDATE assistants_config
      SET metadata = jsonb_set(
            jsonb_set(metadata, '{version}', '"1.1.0"'),
            '{last_updated}', $1::jsonb
          ),
          updated_at = NOW()
      WHERE openai_assistant_id = $2
    `, [JSON.stringify(new Date().toISOString()), assistantId]);

    console.log('✅ Database metadata updated\n');

    console.log('📝 Changes applied:');
    console.log('  1. Enhanced JSON validation with code_interpreter');
    console.log('  2. Made function calls optional (controlled by use_personalization)');
    console.log('  3. Added strict field ordering requirements');
    console.log('  4. Removed markdown code fence wrapping');
    console.log('  5. Added validation checklist\n');

    console.log('✅ Update complete! The assistant is ready to use.');
    console.log('   The changes will take effect immediately for all new requests.\n');

    process.exit(0);
  } catch (error) {
    console.error('❌ Update failed:', error);
    console.error('');
    console.error('Troubleshooting:');
    console.error('- Ensure OPENAI_API_KEY is set in .env');
    console.error('- Ensure the assistant exists (run initialize-assistants.js first)');
    console.error('- Check OpenAI API status: https://status.openai.com/');
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  updatePracticeGenerator();
}

module.exports = { updatePracticeGenerator };
