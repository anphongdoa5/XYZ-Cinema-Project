"use client";
import Link from 'next/link';
import type { SetupReport } from '@/lib/cinema/setup';
import { Shell, Heading, Button, Loading, ErrorBox, useResource } from './ui';

export function SetupScreen() {
  const { data, error, loading, reload } = useResource<SetupReport>('setup');
  return <Shell><main className="page stack" style={{ maxWidth: 1000, margin: '0 auto' }}>
    <Heading label="MÔI TRƯỜNG PHÁT TRIỂN" title="Kiểm tra cài đặt XYZ Cinema" description="Trang này chỉ hoạt động khi chạy npm run dev trên máy của bạn." />
    {loading ? <Loading /> : error ? <ErrorBox message={error} retry={reload} /> : data && <>
      <div className={'notice ' + (data.ready ? 'success' : '')} role="status">{data.ready ? 'Đã sẵn sàng để bắt đầu thử hệ thống.' : 'Còn bước thiết lập cần hoàn tất.'}</div>
      <section className="panel stack">{data.checks.map(check => <div key={check.label} className="stack" style={{ gap: 8 }}><h3>{check.ok ? '✓' : '○'} {check.label}</h3><p className="muted">{check.detail}</p></div>)}</section>
      <section className="panel stack"><h2>Bước tiếp theo</h2><p>{data.nextStep}</p></section>
    </>}
    <section className="panel stack"><h2>Thứ tự cài đặt</h2><ol className="list-decimal pl-5 space-y-3"><li>Supabase → Connect: lấy Project URL và Publishable key; lưu vào <code>.env.local</code>.</li><li>Supabase → SQL Editor → New query: nếu đã cài Chương 3, dán toàn bộ <code>supabase/upgrade.sql</code> rồi Run để giữ dữ liệu. Database mới hoàn toàn dùng <code>supabase/install.sql</code>.</li><li>Đăng ký tài khoản trên website. Khách hàng và nhân viên dùng tài khoản trong database của XYZ Cinema.</li><li>Khởi động lại ứng dụng rồi thử chọn phim và ghế.</li></ol></section>
    <div className="row"><Button size="lg" onClick={reload}>Kiểm tra lại</Button><Button size="lg" variant="outline" asChild><Link href="/">Mở trang chủ</Link></Button></div>
  </main></Shell>;
}
