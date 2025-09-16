const { createClient } = require('@supabase/supabase-js');

let supabase = null;
let supabaseAdmin = null;

// Initialize Supabase client only if credentials are available
if (process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY) {
  supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_ANON_KEY
  );

  // Initialize Supabase admin client (for server-side operations)
  if (process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_ANON_KEY) {
    supabaseAdmin = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_ANON_KEY
    );
  }
  
  console.log('✅ Supabase clients initialized');
} else {
  console.log('ℹ️ Supabase credentials not found - database operations disabled');
}

module.exports = {
  supabase,
  supabaseAdmin
};