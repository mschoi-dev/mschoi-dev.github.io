// Supabase client — shared by signup / login / downloads pages.
// The publishable key is safe to expose; access control lives in RLS policies.
const SUPABASE_URL = 'https://kqobregejyafvvzmccym.supabase.co';
const SUPABASE_KEY = 'sb_publishable_ZiRBBYInbAi2mBE76eqbWQ_hB4WCsTR';
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
