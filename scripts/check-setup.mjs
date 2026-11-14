import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const envFile = path.join(root, '.env.local');
if (!fs.existsSync(envFile)) { console.error('Chưa có .env.local. Sao chép .env.example và điền hai giá trị từ Supabase → Connect.'); process.exit(1); }
process.loadEnvFile(envFile);
const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
if (!url || !key || url.includes('xyz-cinema-dev.supabase.co') || /YOUR_|PROJECT_REF|your-project/i.test(url)) {
  console.error('Project URL hoặc Publishable key chưa được cấu hình bằng giá trị thật. Vào Supabase → Connect, sao chép hai giá trị và lưu vào .env.local.'); process.exit(1);
}
if (key.startsWith('sb_secret_')) { console.error('Biến NEXT_PUBLIC_ đang dùng Secret key. Hãy thay bằng Publishable key.'); process.exit(1); }
if ((!key.startsWith('sb_publishable_') && !key.startsWith('eyJ')) || /YOUR_|REPLACE_WITH|\.\.\./i.test(key)) {
  console.error('Publishable key chưa đúng định dạng. Sao chép lại khóa công khai trong Supabase → Connect.'); process.exit(1);
}
if (key.startsWith('eyJ')) {
  try { if (JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString()).role !== 'anon') throw new Error(); }
  catch { console.error('Khóa cũ phải là anon key hợp lệ. Không dùng service_role key trong biến NEXT_PUBLIC_.'); process.exit(1); }
}
try {
  const parsed = new URL(url);
  const local = ['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname);
  if (parsed.username || parsed.password || parsed.pathname !== '/' || parsed.search || parsed.hash || (parsed.protocol !== 'https:' && !(local && parsed.protocol === 'http:'))) throw new Error('Invalid URL');
  const response = await fetch(`${parsed.origin}/rest/v1/phim?select=phim_id&limit=1000`, { headers: { apikey: key }, signal: AbortSignal.timeout(10000) });
  const data = await response.json();
  if (response.status === 401 || response.status === 403) { console.error('Supabase từ chối khóa hoặc quyền đọc. Kiểm tra đúng project và chạy SQL phân quyền.'); process.exit(1); }
  if (!response.ok) { console.error('Đã kết nối project nhưng chưa đọc được bảng phim. Chạy supabase/deploy.sql trong SQL Editor.'); process.exit(1); }
  console.log(`Kết nối thành công. Đọc được ${Array.isArray(data) ? data.length : 0} phim.`);
  const versionResponse = await fetch(parsed.origin+'/rest/v1/rpc/cinema_version', { method:'POST', headers:{apikey:key,'Content-Type':'application/json'}, body:'{}', signal:AbortSignal.timeout(10000) });
  const version = await versionResponse.json();
  if (!versionResponse.ok || version !== 'chapter3-three-roles-v3') {
    console.error('Database cần cập nhật. Mở supabase/deploy.sql, Ctrl+A → Ctrl+C; Supabase → SQL Editor → New query → dán toàn bộ → Run. Không chạy reset.sql. Dữ liệu hiện có được giữ nguyên.'); process.exit(1);
  }
  console.log('Phiên bản nghiệp vụ: chapter3-three-roles-v3.');
  console.log('Tiếp theo: npm.cmd run dev → http://localhost:3000/cai-dat để kiểm tra các danh mục và dữ liệu mẫu.');
} catch { console.error('Chưa kết nối được Supabase. Kiểm tra Project URL gốc, mạng và trạng thái hoạt động của project.'); process.exit(1); }
