// Local OpenAI API test script
require('dotenv').config();

// Test OpenAI API integration locally
async function testOpenAI() {
    console.log('🔍 Testing OpenAI API integration locally...');
    console.log('📋 Environment check:');
    console.log(`- API Key exists: ${!!process.env.OPENAI_API_KEY}`);
    console.log(`- API Key length: ${process.env.OPENAI_API_KEY ? process.env.OPENAI_API_KEY.length : 0}`);
    console.log(`- API Key prefix: ${process.env.OPENAI_API_KEY ? process.env.OPENAI_API_KEY.substring(0, 7) : 'none'}`);
    
    if (!process.env.OPENAI_API_KEY) {
        console.error('❌ No OpenAI API key found in environment');
        return;
    }

    const testQuestion = "What is 2 + 2?";
    const testSubject = "mathematics";

    console.log(`\n🤖 Testing question: "${testQuestion}"`);
    console.log(`📚 Subject: ${testSubject}`);

    try {
        console.log('\n📡 Making request to OpenAI API...');
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
                'Content-Type': 'application/json',
                'User-Agent': 'StudyAI-Backend/1.0'
            },
            body: JSON.stringify({
                model: 'gpt-4o-mini',
                messages: [
                    {
                        role: 'system',
                        content: `You are an AI homework helper. Provide clear, educational explanations that help students learn. For the subject "${testSubject}", analyze the question and provide a comprehensive answer with step-by-step explanation when appropriate.`
                    },
                    {
                        role: 'user',
                        content: testQuestion
                    }
                ],
                max_tokens: 1000,
                temperature: 0.3
            })
        });

        console.log(`📊 Response status: ${response.status}`);
        console.log(`📊 Response headers:`, Object.fromEntries(response.headers.entries()));

        if (!response.ok) {
            const errorText = await response.text();
            console.error(`❌ OpenAI API error: ${response.status}`);
            console.error(`❌ Error response: ${errorText}`);
            throw new Error(`OpenAI API error: ${response.status} - ${errorText}`);
        }

        const data = await response.json();
        console.log('\n✅ OpenAI Response:');
        console.log('📄 Full response:', JSON.stringify(data, null, 2));
        
        const aiAnswer = data.choices[0]?.message?.content || 'No response generated';
        console.log(`\n🎯 AI Answer: ${aiAnswer}`);
        console.log(`📊 Usage:`, data.usage);
        
        return {
            success: true,
            answer: aiAnswer,
            usage: data.usage
        };

    } catch (error) {
        console.error('\n❌ Test failed:');
        console.error(`- Error type: ${error.constructor.name}`);
        console.error(`- Error message: ${error.message}`);
        console.error(`- Error stack:`, error.stack);
        
        if (error.cause) {
            console.error(`- Error cause:`, error.cause);
        }
        
        return {
            success: false,
            error: error.message
        };
    }
}

// Run the test
testOpenAI().then(result => {
    console.log('\n🏁 Test completed');
    console.log('📊 Final result:', result);
}).catch(error => {
    console.error('\n💥 Unexpected error:', error);
});