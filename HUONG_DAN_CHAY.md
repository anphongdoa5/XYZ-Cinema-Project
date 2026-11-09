# Chạy XYZ Cinema theo Chương 3

Mã nguồn dùng Next.js, React, TypeScript và Supabase PostgreSQL. Đăng ký/đăng nhập dùng bảng `khach_hang`/`nhan_vien` và mật khẩu bcrypt theo Chương 3, không dùng Supabase Auth. VNPay chưa tích hợp; thu/hoàn hiện là mô phỏng.

## 1. Kết nối

Giữ Project URL và Publishable key thật trong `.env.local`:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
APP_URL=http://localhost:3000
```

Không cần Secret key hay service_role key. Không đưa khóa bí mật vào biến `NEXT_PUBLIC_`. Không commit `.env.local`.

## 2. Cập nhật database đang dùng

Database hiện tại đã kết nối và có dữ liệu Chương 3. Bản rà soát ngày 09/11/2026 dùng phiên bản `chapter3-audit-v2`.

1. Trong VS Code, Ctrl+P → nhập `supabase/upgrade.sql` → Enter.
2. Trong tệp đó, Ctrl+A → Ctrl+C để sao chép TOÀN BỘ SQL.
3. Mở đúng project Supabase → SQL Editor → New query; Ctrl+V → Run.
4. Thành công sẽ có kết quả `chapter3-audit-v2`. Tài khoản, mật khẩu, đơn, vé, giao dịch và dữ liệu danh mục được giữ nguyên. Có thể chạy lại tệp nâng cấp.
5. Nếu chưa bật quét hết hạn định kỳ, chạy `supabase/enable-expiry-job.sql` một lần.
6. Khởi động lại website theo bước 3, mở `/cai-dat`; tất cả kiểm tra cần đạt.

**Không chạy reset.sql hoặc install.sql trước upgrade.sql.** Nếu SQL báo lỗi, giữ nguyên thông báo để kiểm tra; giao dịch nâng cấp sẽ rollback khi lỗi. Chưa có tệp SQL nào được tự động chạy trên project Supabase thật trong lần rà soát này.

Chỉ với database mới hoàn toàn: chạy `supabase/install.sql` để tạo cấu trúc và dữ liệu mẫu. `reset.sql` chỉ dành cho việc chủ động xóa dữ liệu phát triển; đọc `supabase/README.md` trước khi dùng. Bản nâng cấp giữ đủ 15 bảng nghiệp vụ theo Chương 3, không chuyển sang Supabase Auth.

## 3. Chạy trên Windows

```powershell
Set-Location -LiteralPath 'E:\HT\ĐỒ ÁN TỐT NGHIỆP\project'
npm.cmd run dev
```

Mở http://localhost:3000/cai-dat để kiểm tra; trang này chỉ có khi chạy dev. Sau khi đổi `.env.local`, dừng tiến trình cũ bằng Ctrl+C rồi chạy lại.

```powershell
node scripts/check-setup.mjs
npm.cmd run lint
npm.cmd run build
```

## 4. Tài khoản và dữ liệu mẫu

Khu nhân viên riêng: http://localhost:3000/admin. Có thể đăng nhập khách hàng và nhân viên đồng thời trong cùng trình duyệt; đăng xuất bên nào chỉ thoát bên đó. Chi tiết bố cục theo 33 ảnh và kiểm tra hai phiên tại [ADMIN_VA_GIAO_DIEN.md](ADMIN_VA_GIAO_DIEN.md). Không cần chạy lại SQL cho thay đổi này.

Thiết kế ghế hỗ trợ nhấn hoặc kéo một vùng để chọn nhiều ô; kéo từ ô đã chọn để bỏ chọn. Các trường ngày trong quản trị có nút lịch để chọn ngày/tháng/năm và vẫn nhập tay được. Truy cập admin trực tiếp bằng địa chỉ trên; footer trang khách không còn liên kết Nhân viên hoặc trang Chính sách.

Không có mật khẩu đăng nhập mẫu cố định. Đăng ký khách hàng qua website. Để tạo nhân viên từ tài khoản vừa đăng ký, sửa email/tên đăng nhập trong `supabase/grant-staff.sql`, chạy bằng SQL Editor, rồi vào `/admin/login`.

Có 6 phim, 7 thể loại, 3 phòng, 3 loại ghế, 234 đơn vị/252 chỗ và lịch mở bán hôm nay đến 4 ngày sau theo giờ Việt Nam. Chạy lại `supabase/seed.sql` khi cần thêm lịch mẫu. Dữ liệu mẫu dùng phim minh họa.

Đổi mật khẩu tại `/auth/update-password`, cần mật khẩu hiện tại. Gửi thư khôi phục chưa cấu hình; dùng quy trình hỗ trợ/`supabase/reset-password.sql` của DB owner. Bản này không cần cấu hình Supabase Authentication → URL Configuration hoặc email template.

## 5. Nghiệp vụ

Giữ ghế tối đa 8 đơn vị trong 10 phút; ghế đôi là 1 đơn vị gồm 2 chỗ. Chốt giá khi tạo đơn và có 10 phút mới để thanh toán. Đóng giữ mới trước giờ chiếu 15 phút. Lịch gồm thời lượng phim + 15 phút quảng cáo, sau đó 15 phút dọn phòng. Khuyến mãi được kiểm tra lại lúc thanh toán; thanh toán/hoàn lặp không sinh thêm vé/giao dịch. Hủy toàn bộ đơn đã trả trước ít nhất 2 giờ, hoàn 100% thực trả; rạp ngừng suất không áp dụng ngưỡng này. Lịch sử vé hủy được giữ khi ghế được bán lại.

Để thử provider mô phỏng trong SQL Editor:

```sql
update cinema_private.cau_hinh set simulation_outcome='success' where id;
-- Có thể thay 'success' bằng 'failed' hoặc 'timeout'.
```

VNPay Sandbox có dòng danh mục trạng thái tắt; chưa có xử lý kết nối/gọi cổng/nhận IPN. QR mã hóa `ma_ve`, được tra cứu cùng trạng thái hiện hành.

## 6. Kết quả rà soát 09/11/2026

Đã qua 90 tình huống cục bộ và 5 kiểm tra trên Supabase thật. Đã xác nhận phiên bản `chapter3-audit-v2`, danh mục, sơ đồ ghế và quyền truy cập. Xem [KIEM_THU_HE_THONG.md](KIEM_THU_HE_THONG.md) để biết phạm vi từng nhóm chức năng và các sửa lỗi. Có thể chạy lại 10 kiểm tra báo cáo bằng `node scripts/tests/reports.mjs`.

Luồng ghi dữ liệu được kiểm tra với Next.js và PostgreSQL riêng; chưa kiểm thử tải nhiều kết nối hoặc tạo đơn/thu/hoàn trên database thật.

Giao diện tiếp tục dùng token, font Manrope, SVG và các thành phần từ Figma đã triển khai. Giới hạn lượt đọc Figma trước đây vẫn khiến chưa đối chiếu được mọi frame/popup quản trị; chưa khẳng định mọi màn hình khớp tuyệt đối.

Tâm điểm theo vé bán: chạy `supabase/update-weekly-feature.sql` một lần trong SQL Editor (kết quả `weekly-feature-v1`), rồi tải lại trang chủ. Không chạy reset/install. Phim được chọn theo số vé đã thanh toán, chưa hủy trong tuần thứ Hai–Chủ nhật theo giờ Việt Nam.
