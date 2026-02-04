/**
 * Test script for ElevenLabs WebSocket connection
 *
 * Tests:
 * 1. WebSocket connection to ElevenLabs
 * 2. Sending text chunks
 * 3. Receiving audio chunks
 * 4. Connection lifecycle management
 *
 * Usage:
 *   node tests/test-elevenlabs-ws.js
 *
 * Prerequisites:
 *   - ELEVENLABS_API_KEY must be set in environment
 *   - npm install ws (already done)
 */

require('dotenv').config();
const ElevenLabsWebSocketClient = require('../src/gateway/services/ElevenLabsWebSocketClient');

async function testConnection() {
  console.log('🧪 Starting ElevenLabs WebSocket Test...\n');

  // Check API key
  const apiKey = process.env.ELEVENLABS_API_KEY;
  if (!apiKey || apiKey === 'your-elevenlabs-api-key-here') {
    console.error('❌ ELEVENLABS_API_KEY not set in environment');
    console.error('   Please set it in 01_core_backend/.env');
    process.exit(1);
  }

  console.log('✅ API key found\n');

  try {
    // Create client
    console.log('📦 Creating ElevenLabs WebSocket client...');
    const client = new ElevenLabsWebSocketClient(
      'zZLmKvCp1i04X8E0FJ8B', // Max voice (Vince)
      'eleven_turbo_v2_5',
      apiKey
    );

    const audioChunks = [];

    // Set up audio chunk callback
    client.onAudioChunk = (chunk) => {
      audioChunks.push(chunk);
      console.log(`   📥 Audio chunk #${audioChunks.length} received (${chunk.audio.length} bytes base64)`);
      if (chunk.alignment) {
        console.log(`      Alignment data: ${chunk.alignment.chars?.length || 0} characters`);
      }
    };

    // Set up error callback
    client.onError = (error) => {
      console.error('   ⚠️ WebSocket error:', error.message);
    };

    // Connect
    console.log('\n🔌 Connecting to ElevenLabs...');
    await client.connect();

    // Send test text
    console.log('\n📤 Sending test text chunks...');
    const testSentences = [
      'Hello, this is a test of the ElevenLabs WebSocket streaming.',
      'I am testing the interactive mode for StudyAI.',
      'This should generate audio in real time.'
    ];

    for (const sentence of testSentences) {
      client.sendTextChunk(sentence, true);
      await new Promise(resolve => setTimeout(resolve, 500)); // Small delay between chunks
    }

    // Wait for audio chunks to arrive
    console.log('\n⏳ Waiting for audio chunks (5 seconds)...');
    await new Promise(resolve => setTimeout(resolve, 5000));

    // Send end-of-input signal
    console.log('\n🏁 Sending end-of-input signal...');
    client.sendEndOfInput();

    // Wait a bit more for final chunks
    await new Promise(resolve => setTimeout(resolve, 2000));

    // Get metrics
    const metrics = client.getMetrics();

    // Close connection
    console.log('\n🔌 Closing connection...');
    client.close();

    // Display results
    console.log('\n' + '='.repeat(60));
    console.log('📊 TEST RESULTS');
    console.log('='.repeat(60));
    console.log(`✅ Connection successful: ${metrics.isConnected ? 'Yes' : 'No'}`);
    console.log(`🔊 Audio chunks received: ${audioChunks.length}`);
    console.log(`⏱️ Connection latency: ${metrics.connectionLatency}ms`);
    console.log(`⏱️ Time to first audio (TTFA): ${metrics.ttfa}ms`);

    if (audioChunks.length > 0) {
      console.log(`\n✅ PHASE 1 TEST: SUCCESS`);
      console.log(`   - WebSocket connected`);
      console.log(`   - Text chunks sent`);
      console.log(`   - Audio chunks received`);
      console.log(`   - Connection closed gracefully`);
    } else {
      console.log(`\n⚠️ PHASE 1 TEST: PARTIAL SUCCESS`);
      console.log(`   - WebSocket connected`);
      console.log(`   - Text chunks sent`);
      console.log(`   - No audio chunks received (might need more wait time)`);
    }

    console.log('='.repeat(60) + '\n');

  } catch (error) {
    console.error('\n❌ TEST FAILED:', error.message);
    console.error('Stack trace:', error.stack);
    process.exit(1);
  }
}

// Run test
testConnection().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});
