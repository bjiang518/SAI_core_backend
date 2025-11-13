#!/usr/bin/env node

/**
 * Update Practice Generator Assistant Instructions (Standalone)
 *
 * Updates the existing Practice Generator assistant with new instructions
 * WITHOUT requiring database connection
 *
 * Usage: node scripts/update-practice-generator-standalone.js ASSISTANT_ID
 * Example: node scripts/update-practice-generator-standalone.js asst_abc123xyz
 */

require('dotenv').config();
const OpenAI = require('openai');
const { PRACTICE_GENERATOR_INSTRUCTIONS } = require('../src/services/assistants/practice-generator-assistant');

async function updatePracticeGenerator() {
  const assistantId = process.argv[2];

  if (!assistantId) {
    console.error('❌ Error: Assistant ID is required');
    console.error('Usage: node scripts/update-practice-generator-standalone.js ASSISTANT_ID');
    console.error('');
    console.error('You can find your assistant ID in Railway logs or from OpenAI dashboard');
    process.exit(1);
  }

  if (!process.env.OPENAI_API_KEY) {
    console.error('❌ Error: OPENAI_API_KEY not set in .env file');
    process.exit(1);
  }

  console.log('🔄 Updating Practice Generator Assistant instructions...\n');
  console.log(`Assistant ID: ${assistantId}\n`);

  try {
    const client = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY
    });

    // Update assistant instructions via OpenAI API
    console.log('🔧 Sending update to OpenAI...');
    const updatedAssistant = await client.beta.assistants.update(
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

    console.log('📝 Changes applied:');
    console.log('  1. Enhanced JSON validation requirements');
    console.log('  2. Made function calls optional (controlled by use_personalization)');
    console.log('  3. Added strict field ordering requirements');
    console.log('  4. Removed markdown code fence wrapping');
    console.log('  5. Clearer personalization rules\n');

    console.log('✅ Update complete! The assistant is ready to use.');
    console.log('   The changes will take effect immediately for all new requests.\n');

    console.log('💡 Next step: Test from your iOS app to verify JSON output is now correct!');

    process.exit(0);
  } catch (error) {
    console.error('❌ Update failed:', error.message);
    console.error('');
    console.error('Troubleshooting:');
    console.error('- Verify the Assistant ID is correct');
    console.error('- Ensure OPENAI_API_KEY has access to this assistant');
    console.error('- Check OpenAI API status: https://status.openai.com/');
    process.exit(1);
  }
}

// Run
updatePracticeGenerator();
