// Quick test of AI service
require('dotenv').config();

async function testAI() {
  console.log('🤖 Testing OpenAI API connection...\n');
  
  try {
    // Test OpenAI directly
    const OpenAI = require('openai');
    const openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });

    console.log('🔑 API Key loaded:', process.env.OPENAI_API_KEY ? 'Yes' : 'No');
    console.log('🔑 Key starts with:', process.env.OPENAI_API_KEY?.substring(0, 10) + '...');

    const response = await openai.chat.completions.create({
      model: "gpt-3.5-turbo",
      messages: [{ role: "user", content: "Hello" }],
      max_tokens: 5
    });

    console.log('✅ OpenAI API connection successful!');
    console.log('📝 Response:', response.choices[0].message.content);
    console.log('🚀 AI features are ready to use!');
    
  } catch (error) {
    console.log('❌ AI test failed:', error.message);
    console.log('📋 Error details:', error.code || 'Unknown error code');
  }
}

testAI();