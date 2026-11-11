# XYZ Cinema - Hệ thống đặt vé xem phim
Sinh viên thực hiện: Huỳnh Văn Chí An
\nMSSV: 030239230001
\nLớp: DH39CDS02
\nGVHD: ThS.Nguyễn Thị Tường Vi

Ứng dụng đồ án dùng Next.js, React, TypeScript và Supabase PostgreSQL bao gồm các chức năng như đặt ghế, khuyến mãi, thanh toán mô phỏng/VNPay Sandbox, vé QR, quản lý rạp và báo cáo.

## Cài đặt:

1. Tạo project Supabase, mở SQL Editor bằng role `postgres` và chạy **toàn bộ [supabase/deploy.sql](supabase/deploy.sql) một lần**. Kết quả: `xyz-cinema-deploy-v1`.
2. Sao chép `.env.example` thành `.env.local`, điền Project URL/Publishable key; điền thêm các biến VNPay nếu thử cổng thanh toán.
3. Tại thư mục mã nguồn: `npm ci`, rồi `npm run dev` (Node.js 22 trở lên).
4. Mở http://localhost:3000. Khu nhân viên: `/admin/login`, tài khoản mẫu `admin` / `admin`. Khách hàng đăng ký trên website.

Xem **[hướng dẫn triển khai đầy đủ](HUONG_DAN_CHAY.md)** để cấu hình VNPay, chạy production và kiểm tra kết nối.



