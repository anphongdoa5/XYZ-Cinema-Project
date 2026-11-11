import 'server-only';
import { publicSupabaseConfig } from '@/lib/supabase/config';

export type SetupCheck = { label: string; ok: boolean; detail: string };
export type SetupReport = { ready: boolean; checks: SetupCheck[]; nextStep: string };

export async function checkSetup(): Promise<SetupReport> {
  const config = publicSupabaseConfig();
  if (!config.ok) return { ready: false, checks: [{ label: 'Cấu hình kết nối', ok: false, detail: config.message }], nextStep: 'Cập nhật hai biến NEXT_PUBLIC_SUPABASE_URL và NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY trong .env.local, sau đó khởi động lại ứng dụng.' };
  const checks: SetupCheck[] = [{ label: 'Cấu hình kết nối', ok: true, detail: 'Đã có Project URL và khóa công khai đúng định dạng.' }];
  try {
    const paths = ['phim', 'phong_chieu', 'suat_chieu', 'ghe'];
    const primaryKeys:Record<string,string>={phim:'phim_id',phong_chieu:'phong_chieu_id',suat_chieu:'suat_chieu_id',ghe:'ghe_id'};
    const results = await Promise.all(paths.map(async table => {
      const response = await fetch(`${config.url}/rest/v1/${table}?select=${primaryKeys[table]}&limit=1000`, {
        headers: { apikey: config.key }, cache: 'no-store', signal: AbortSignal.timeout(8000),
      });
      const body = await response.json();
      return { table, status: response.status, ok: response.ok, code: body?.code, count: Array.isArray(body) ? body.length : 0 };
    }));
    const rejected = results.find(r => r.status === 401 || r.status === 403);
    if (rejected) {
      checks.push({ label: 'Kết nối Supabase', ok: false, detail: 'Supabase từ chối khóa hoặc quyền đọc dữ liệu. Kiểm tra khóa có thuộc đúng project và đã chạy SQL phân quyền chưa.' });
      return { ready: false, checks, nextStep: 'Lấy lại Publishable key của đúng project, rồi chạy toàn bộ supabase/deploy.sql trong SQL Editor để cài mới hoặc cập nhật phân quyền.' };
    }
    checks.push({ label: 'Kết nối Supabase', ok: true, detail: 'Project đã phản hồi.' });
    if (results.some(r => !r.ok)) {
      checks.push({ label: 'Cấu trúc database', ok: false, detail: 'Chưa đọc được đầy đủ các bảng phim, phòng, suất chiếu và ghế.' });
      return { ready: false, checks, nextStep: 'Chạy toàn bộ supabase/deploy.sql trong SQL Editor bằng role postgres. Tệp tự cài mới hoặc cập nhật bản Chương 3 được hỗ trợ và giữ dữ liệu.' };
    }
    checks.push({ label: 'Cấu trúc database', ok: true, detail: 'Đọc được bốn bảng danh mục qua chính sách truy cập công khai.' });
    const versionResponse = await fetch(`${config.url}/rest/v1/rpc/cinema_version`, {
      method: 'POST', headers: { apikey: config.key, 'Content-Type': 'application/json' }, body: '{}', cache: 'no-store', signal: AbortSignal.timeout(8000),
    });
    const version = await versionResponse.json();
    const currentVersion = versionResponse.ok && version === 'chapter3-audit-v2';
    checks.push({ label: 'Phiên bản nghiệp vụ', ok: currentVersion, detail: currentVersion ? 'Đã cập nhật chapter3-audit-v2.' : 'Database đã có danh mục nhưng cần cập nhật các hàm nghiệp vụ và báo cáo.' });
    if (!currentVersion) return { ready: false, checks, nextStep: 'Supabase → SQL Editor → New query (role postgres): dán TOÀN BỘ supabase/deploy.sql rồi Run. Tệp giữ dữ liệu hiện có; không cần chạy các bản vá riêng.' };
    const labels: Record<string, string> = { phim: 'phim', phong_chieu: 'phòng', suat_chieu: 'suất chiếu', ghe: 'đơn vị ghế' };
    const hasData = results.every(r => r.count > 0);
    checks.push({ label: 'Dữ liệu để bắt đầu', ok: hasData, detail: results.map(r => `${r.count} ${labels[r.table]}`).join(' · ') });
    return { ready: hasData, checks, nextStep: hasData ? 'Mở trang chủ, đăng ký khách hàng và thử đặt vé. Bản cài mới bằng deploy.sql có admin/admin tại /admin/login; database đã có admin giữ mật khẩu hiện tại.' : 'Chạy supabase/seed.sql hoặc thêm dữ liệu trong khu vực quản trị.' };
  } catch {
    checks.push({ label: 'Kết nối Supabase', ok: false, detail: 'Không nhận được phản hồi hợp lệ trong thời gian kiểm tra.' });
    return { ready: false, checks, nextStep: 'Kiểm tra mạng, Project URL và trạng thái project trong Supabase Dashboard. Project bị tạm dừng cần được khôi phục trước.' };
  }
}
