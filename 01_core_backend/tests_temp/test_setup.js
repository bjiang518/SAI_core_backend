// Simple test to check if our setup works
require('dotenv').config();

console.log('🔍 Testing StudyAI Backend Setup...');

// Test environment variables
console.log('📋 Environment Check:');
console.log('- NODE_ENV:', process.env.NODE_ENV || 'development');
console.log('- PORT:', process.env.PORT || 'not set');
console.log('- SUPABASE_URL:', process.env.SUPABASE_URL ? '✅ Set' : '❌ Missing');
console.log('- SUPABASE_ANON_KEY:', process.env.SUPABASE_ANON_KEY ? '✅ Set' : '❌ Missing');

// Test Supabase connection
console.log('\n🔌 Testing Supabase Connection...');
try {
  const { createClient } = require('@supabase/supabase-js');
  const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_ANON_KEY
  );
  console.log('✅ Supabase client created successfully');
} catch (error) {
  console.log('❌ Supabase connection failed:', error.message);
}

// Test Express setup
console.log('\n⚡ Testing Express Setup...');
try {
  const express = require('express');
  const app = express();
  console.log('✅ Express loaded successfully');
} catch (error) {
  console.log('❌ Express setup failed:', error.message);
}

console.log('\n🎉 Setup test completed!');