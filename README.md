# XYZ Cinema - Hệ thống đặt vé xem phim
Sinh viên thực hiện: Huỳnh Văn Chí An

MSSV: 030239230001

Lớp: DH39CDS02

GVHD: ThS.Nguyễn Thị Tường Vi

Ứng dụng đồ án dùng Next.js, React, TypeScript và Supabase PostgreSQL bao gồm các chức năng như đặt ghế, khuyến mãi, thanh toán mô phỏng/VNPay Sandbox, vé QR, quản lý rạp và báo cáo.

Test trực tiếp hệ thống tại: https://xyzcinema.vercel.app/
## Hoặc cài đặt tại local:

1. Tạo project Supabase, mở SQL Editor bằng role `postgres` và chạy **toàn bộ [supabase/deploy.sql](supabase/deploy.sql) một lần**. Kết quả: `xyz-cinema-three-roles-v3`.
2. Sao chép `.env.example` thành `.env.local`, điền Project URL/Publishable key; điền thêm các biến VNPay nếu thử cổng thanh toán.
3. Tại thư mục mã nguồn: `npm ci`, rồi `npm run dev` (Node.js 22 trở lên).
4. Mở http://localhost:3000. Khu nội bộ: `/admin/login`, tài khoản mẫu `admin` / `admin`. Khách hàng đăng ký trên website.

Xem **[hướng dẫn triển khai đầy đủ](HUONG_DAN_CHAY.md)** để cấu hình VNPay, chạy production và kiểm tra kết nối.




## Cài lại theo mô hình ba vai trò

Chạy toàn bộ **[supabase/reset-and-deploy.sql](supabase/reset-and-deploy.sql)** một lần trong Supabase SQL Editor (role postgres). Script xóa dữ liệu XYZ Cinema và tạo lại đầy đủ; không xóa Auth/Storage hoặc bảng ứng dụng khác.

Quản trị: `admin / admin`. Nhân viên: `nv01`–`nv05 / Nhanvien123!`. Đăng nhập ở `/admin/login` và được điều hướng theo đúng vai trò.
