// Supabase client — shared by all pages that need auth.
// The publishable key is safe to expose; access control lives in RLS policies.
const SUPABASE_URL = 'https://kqobregejyafvvzmccym.supabase.co';
const SUPABASE_KEY = 'sb_publishable_ZiRBBYInbAi2mBE76eqbWQ_hB4WCsTR';
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// Nav: signed-in users get a profile button; members with community
// access (and admins) additionally see the hidden Community link.
(async () => {
  const link = document.querySelector('.nav-signin');
  if (!link) return;
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return;

  const { data: p } = await sb.from('profiles')
    .select('full_name, role').eq('id', session.user.id).single();
  link.textContent = (p && p.full_name) ? p.full_name : 'My Profile';
  link.setAttribute('href', 'profile.html');

  let showCommunity = p && p.role === 'admin';
  if (!showCommunity) {
    const { count } = await sb.from('community_access')
      .select('*', { count: 'exact', head: true }).eq('user_id', session.user.id);
    showCommunity = (count || 0) > 0;
  }
  if (showCommunity) {
    const navLinks = document.querySelector('.nav-links');
    const contact = navLinks && navLinks.querySelector('a[href$="contact.html"]');
    if (contact && !navLinks.querySelector('a[href$="community.html"]')) {
      const a = document.createElement('a');
      a.href = 'community.html';
      a.textContent = 'Community';
      if (location.pathname.endsWith('community.html')) a.className = 'active';
      navLinks.insertBefore(a, contact);
    }
  }
})();
