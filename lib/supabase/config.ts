/** Public connection settings only. Never read a secret/service-role key here. */
export function validateSupabaseConfig(url: string | undefined, key: string | undefined) {
  if (!url?.trim() || !key?.trim()) {
    return { ok: false as const, message: 'Chưa có Project URL hoặc Publishable key. Hãy lấy hai giá trị trong Supabase → Connect và lưu vào .env.local.' };
  }
  let parsed: URL;
  try { parsed = new URL(url.trim()); } catch {
    return { ok: false as const, message: 'Project URL chưa hợp lệ. Hãy sao chép nguyên địa chỉ HTTPS từ Supabase → Connect.' };
  }
  const local = ['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname);
  if (parsed.username || parsed.password || (parsed.protocol !== 'https:' && !(local && parsed.protocol === 'http:'))) {
    return { ok: false as const, message: 'Project URL phải là địa chỉ HTTPS của project Supabase hoặc địa chỉ Supabase cục bộ.' };
  }
  if (parsed.pathname !== '/' || parsed.search || parsed.hash) {
    return { ok: false as const, message: 'Dùng Project URL gốc, không dùng đường dẫn Dashboard, /rest/v1 hoặc /auth/v1.' };
  }
  if (parsed.hostname === 'xyz-cinema-dev.supabase.co' || /YOUR_|PROJECT_REF|your-project|example\./i.test(url)) {
    return { ok: false as const, message: 'Project URL hiện là giá trị minh họa. Tên project không phải địa chỉ kết nối; hãy lấy URL thật trong Supabase → Connect.' };
  }
  const publicKey = key.trim();
  if (/^sb_secret_/.test(publicKey)) {
    return { ok: false as const, message: 'Ô Publishable key đang dùng Secret key. Hãy thay bằng Publishable key; không dùng Secret key phía trình duyệt.' };
  }
  if ((!publicKey.startsWith('sb_publishable_') && !publicKey.startsWith('eyJ')) || /YOUR_|your-publishable|REPLACE_WITH|\.\.\./i.test(publicKey)) {
    return { ok: false as const, message: 'Publishable key chưa đúng định dạng. Sao chép Publishable key từ Supabase → Connect hoặc Settings → API Keys.' };
  }
  if (publicKey.startsWith('eyJ')) {
    try {
      const claims = JSON.parse(atob(publicKey.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
      if (claims.role !== 'anon') return { ok: false as const, message: 'Khóa cũ phải là anon key. Không dùng service_role key trong biến NEXT_PUBLIC_.' };
    } catch { return { ok: false as const, message: 'Anon key cũ chưa hợp lệ. Hãy sao chép lại Publishable key của project.' }; }
  }
  return { ok: true as const, url: parsed.origin, key: publicKey };
}

export function publicSupabaseConfig() {
  return validateSupabaseConfig(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
}

export function requireSupabaseConfig() {
  const result = publicSupabaseConfig();
  if (!result.ok) throw new Error(result.message);
  return result;
}
