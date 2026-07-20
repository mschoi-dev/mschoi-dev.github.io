// Supabase client — shared by all pages that need auth.
// The publishable key is safe to expose; access control lives in RLS policies.
const SUPABASE_URL = 'https://kqobregejyafvvzmccym.supabase.co';
const SUPABASE_KEY = 'sb_publishable_ZiRBBYInbAi2mBE76eqbWQ_hB4WCsTR';
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// Nav: when signed in, turn the "Sign in" pill into a profile button.
(async () => {
  const link = document.querySelector('.nav-signin');
  if (!link) return;
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return;
  const { data: p } = await sb.from('profiles')
    .select('full_name').eq('id', session.user.id).single();
  link.textContent = (p && p.full_name) ? p.full_name : 'My Profile';
  link.setAttribute('href', 'profile.html');
})();
