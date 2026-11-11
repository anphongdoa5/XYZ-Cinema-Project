# Triển khai XYZ Cinema 

Mã nguồn dùng Next.js, React, TypeScript và Supabase PostgreSQL. Chỉ cần chạy **tệp SQL: [supabase/deploy.sql](supabase/deploy.sql)** để triển khai database và toàn bộ tính năng hiện tại.
## 1. Chuẩn bị

- Node.js 22 trở lên và npm; giữ nguyên `package-lock.json` để cài đúng phiên bản thư viện.
- Một project Supabase đang hoạt động. 
- Tài khoản merchant VNPay Sandbox nếu muốn sử dụng cổng VNPay. Chưa có thông tin này vẫn dùng được **Thanh toán mô phỏng**.

Đăng nhập của ứng dụng dùng `khach_hang`/`nhan_vien` và mật khẩu bcrypt.

## 2. Triển khai database bằng một lần Run

1. Mở [supabase/deploy.sql](supabase/deploy.sql), sao chép **toàn bộ nội dung tệp**.
2. Vào đúng project Supabase → **SQL Editor → New query**, chọn role **postgres**.
3. Dán toàn bộ rồi bấm **Run** một lần và đợi hoàn tất.
4. Kết quả cuối cần có `ket_qua = xyz-cinema-deploy-v1`, `bang_nghiep_vu = 15`; các cột `rls_day_du`, `tam_diem_tuan`, `vnpay_confirmation_v2`, `co_tai_khoan_admin`, `cron_het_han` đều là `true`.

Nếu báo không bật được `pg_cron`, kiểm tra project đang hoạt động, role SQL Editor là `postgres` và Supabase → Integrations → Cron. Sau khi bật Cron, chạy lại **chính `deploy.sql`**. Gói cài đặt sẽ chưa commit nếu bước đăng ký Cron thất bại.

## 3. Cấu hình ứng dụng

Trong thư mục gốc mã nguồn, sao chép `.env.example` thành `.env.local` và điền thông tin của **project vừa chạy SQL**:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
APP_URL=http://localhost:3000

# Điền các biến dưới đây nếu thử VNPay Sandbox:
SUPABASE_SECRET_KEY=sb_secret_...
VNPAY_TMN_CODE=MA_WEBSITE_DUOC_CAP
VNPAY_HASH_SECRET=KHOA_CHECKSUM_DUOC_CAP
VNPAY_PAYMENT_URL=https://sandbox.vnpayment.vn/paymentv2/vpcpay.html
VNPAY_RETURN_URL=http://localhost:3000/api/payments/vnpay/return
```

Project URL và Publishable key lấy từ Supabase Dashboard của project. Secret key lấy tại Settings → API Keys → Secret keys; khóa service_role cũ cũng được hỗ trợ trong `SUPABASE_SECRET_KEY`.

SQL không thể cấp mã merchant/khóa VNPay hoặc cấu hình tên miền ứng dụng thay cho người triển khai. Phần này cần điền riêng trên từng máy; không cần chạy thêm SQL. Xem [cấu hình VNPay](docs/VNPAY-SANDBOX.md) cho Return URL và IPN công khai. Hoàn tiền hiện vẫn là mô phỏng; chưa gọi API hoàn tiền VNPay.

## 4. Cài thư viện và khởi động

Mở terminal **tại thư mục mã nguồn chứa `package.json`**:

```sh
npm ci
npm run dev
```

Trên Windows nếu PowerShell chặn `npm.ps1`, dùng `npm.cmd` thay cho `npm`. Mở:

- Trang khách: http://localhost:3000
- Đăng nhập nhân viên: http://localhost:3000/admin/login

Sau khi đổi `.env.local`, dừng server bằng Ctrl+C rồi khởi động lại. Để chạy bản production:

```sh
npm run build
npm start
```

## 5. Tài khoản và dữ liệu demo

**Nhân viên quản trị mẫu:** tên đăng nhập `admin`, mật khẩu `admin`. Tệp chỉ tạo tài khoản khi chưa tồn tại. Nếu chạy lại trên database cũ, dùng mật khẩu admin hiện tại; gói không đặt lại mật khẩu. Có thể đổi mật khẩu tại `/auth/update-password`; nên đổi trước khi công khai hệ thống.

**Khách hàng:** đăng ký ngay trên website bằng email, số điện thoại và mật khẩu tự chọn. 
