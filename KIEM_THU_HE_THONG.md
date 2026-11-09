# Rà soát XYZ Cinema — 09/11/2026

Lần cập nhật tiếp theo tách khu `/admin`, hai phiên đăng nhập và giao diện theo 33 ảnh được ghi tại [ADMIN_VA_GIAO_DIEN.md](ADMIN_VA_GIAO_DIEN.md). Các kết quả dưới đây là đợt kiểm tra database/chức năng trước khi thay giao diện.

Nguồn: `FINAL - ĐỒ ÁN TN.docx`, UC01–UC15, BR01–BR20, Chương 3 mục 3.1 (15 bảng, IR01–IR10), Chương 4 mục 4.3 (báo cáo). Giữ đăng nhập bằng `khach_hang`/`nhan_vien` theo lựa chọn của chủ đồ án. Thanh toán và hoàn tiền là mô phỏng; VNPay chưa tích hợp.

## Kết quả kiểm tra

| Nhóm | Số tình huống đạt | Môi trường |
|---|---:|---|
| Schema, tài khoản, phân quyền, giữ ghế, đơn, khuyến mãi, vé, hoàn tiền | 29 | PostgreSQL qua PGlite, database riêng |
| Chuyển schema cũ và bảo vệ dữ liệu không thuộc XYZ Cinema | 3 | PostgreSQL riêng |
| Nâng cấp v1 → v2 có dữ liệu, nâng cấp lặp, lịch sử mã, NULL, lỗi thanh toán, giới hạn tiền | 10 | PostgreSQL riêng |
| Công thức và bộ lọc báo cáo, múi giờ, URL quay lại an toàn | 10 | Node.js, kết quả kỳ vọng độc lập |
| Đăng ký → đặt vé → áp mã → thanh toán → QR → hủy; đăng nhập nhân viên, CRUD | 8 | Next.js thật + cookie thật + PostgreSQL riêng |
| Giao diện và popup khách hàng/admin, desktop/mobile | 21 | Edge headless, dữ liệu API fixture |
| Sửa nhiều bản ghi, lịch chiếu, mã không giới hạn, CSRF, hủy hộ, báo cáo desktop/mobile | 9 | Next.js thật + PostgreSQL riêng |
| Phiên bản, danh mục, từ chối admin ẩn danh, sơ đồ, bảo vệ cột mật khẩu | 5 | Project Supabase thật, kiểm tra truy cập công khai |
| **Tổng** | **95** | **90 cục bộ + 5 trên Supabase thật** |

Supabase thật đã xác nhận `chapter3-audit-v2`, 6 phim, 3 phòng và 57 suất tương lai tại thời điểm kiểm tra. Chủ project đã chạy `supabase/upgrade.sql` thành công. Không tạo tài khoản, đơn hay giao dịch kiểm thử trên database thật. Đọc sơ đồ có thể thu hồi ghế giữ đã hết hạn theo nghiệp vụ.

## Đối chiếu chức năng

| UC | Phạm vi đã rà soát |
|---|---|
| UC01 | Khách hàng đăng ký/đăng nhập; nhân viên đăng nhập username/email; mật khẩu bcrypt, cookie HttpOnly/SameSite, phân quyền DB/API; đổi mật khẩu thu hồi phiên |
| UC02 | Tìm và lọc phim; chi tiết, trailer YouTube, lịch theo ngày; cập nhật lịch tự động |
| UC03 | Ghế thường/VIP/đôi, ghế khóa; tối đa 8 đơn vị; kiểm tra xung đột, phiên giữ 10 phút, tiếp tục/trả ghế |
| UC04 | Tạo đơn từ phiên giữ thuộc chính khách; chốt giá, hạn thanh toán 10 phút độc lập; xử lý xác nhận lặp |
| UC05 | Một mã/đơn; thời hạn, trạng thái, giá trị tối thiểu, trần, quota; kiểm tra lại khi thanh toán; lưu mã vào snapshot lịch sử |
| UC06 | Thành công/thất bại/timeout của provider mô phỏng; kiểm tra lại giá và quota; thử lại không ghi nhận thu thành công hai lần |
| UC07 | Chỉ phát hành vé sau thu thành công; QR duy nhất theo mã vé; giữ trạng thái vé hủy trong lịch sử |
| UC08 | Danh sách/chi tiết theo chủ tài khoản; tiếp tục đơn còn hạn, vé và giao dịch; khách khác không đọc được |
| UC09 | Hủy toàn bộ đơn đã trả, còn ít nhất 2 giờ, chưa dùng vé; hoàn 100%, liên kết khoản thu gốc, không hoàn trùng |
| UC10 | Thêm/sửa/ngừng phim; chuẩn hóa thể loại; bảo vệ các suất tương lai khi đổi thời lượng/ngừng phim |
| UC11 | Tạo phòng, sơ đồ và loại ghế; ghế đôi chiếm hai chỗ; kiểm tra chồng lấn; khóa cấu trúc đã phát sinh lịch |
| UC12 | Tạo/sửa giá/hủy suất; phim + 15 phút quảng cáo + 15 phút dọn phòng; xác nhận ảnh hưởng trước khi hủy/hoàn |
| UC13 | Tra cứu đơn/vé, chi tiết và hủy hộ khách theo chính sách |
| UC14 | Tạo/sửa/tạm dừng/ngừng mã; hỗ trợ trần và quota NULL; lượt tích lũy giữ cả đơn đã hoàn |
| UC15 | Doanh thu theo ngày thanh toán; thu/hoàn theo ngày giao dịch; lấp đầy theo phòng với trục 0–100%; hiệu quả mã gồm đơn đã hủy |

## Những lỗi đã sửa

- Báo cáo có đủ 5 chỉ số doanh thu, bảng theo ngày và bảng đối chiếu thu/hoàn; giá trị trung bình rỗng hiển thị “—”. Bộ số ví dụ SAO10 của đồ án được kiểm tra: 2 đơn, 1 đơn hủy, giảm 24.000đ, doanh thu 216.000đ, lượt tích lũy 129/500.
- Lấp đầy tính theo số chỗ: đôi = 2, loại ghế khóa/suất ngừng khỏi mẫu số; cộng theo sức chứa từng phòng. Ghế giữ/hủy không tính đã bán. Lịch chiếu admin cũng loại ghế khóa khỏi số trống.
- Biểu mẫu admin được tạo lại khi đổi bản ghi, trang phân trang được đặt lại/kẹp theo bộ lọc; dữ liệu nhập không bị trộn.
- Chọn ghế được làm sạch khi ghế vừa bị người khác giữ; sơ đồ có ghế khóa và kích thước động. Biểu mẫu sơ đồ kiểm tra đầy đủ hai vị trí ghế đôi.
- Tải dữ liệu không chồng các lượt polling; bỏ kết quả cũ sau khi đổi trang; xử lý hết hạn một lần cho mỗi mốc. Các trang theo ID có key riêng để đặt lại trạng thái biểu mẫu/popup khi đổi đối tượng.
- Kiểm tra trường admin tại API trước khi gọi database; xử lý giới hạn tiền và URL quay lại; thông báo lỗi, trang 404 và đăng nhập lại theo đúng ngữ cảnh.
- Bổ sung nâng cấp không xóa dữ liệu, chẩn đoán phiên bản và chỉ mục; giữ nguyên migration đã phát hành.

## Giao diện và phạm vi xác minh

Tiếp tục dùng Manrope, bảng màu và SVG đã lấy từ Figma `yDBoMk92RGzqxhuXmpWsad`. Đã kiểm tra trực quan screenshot trang chủ, ghế, thanh toán, QR, popup hủy, các trang admin và ba báo cáo. Kiểm tra không tràn toàn trang ở 390px; bảng/sơ đồ rộng cuộn bên trong vùng chứa. Popup có focus, nhãn và Escape; thao tác đang xử lý chặn đóng theo luồng.

Figma Starter đã hết lượt đọc API. Lần này không lấy lại được toàn bộ frame; đối chiếu dùng mẫu đã lấy trước đó và đặc tả trong đồ án. Chưa xác nhận từng frame/popup khớp tuyệt đối với phiên bản Figma hiện tại.

PGlite chạy một kết nối; các kiểm tra xung đột/idempotence không thay thế kiểm thử tải với nhiều kết nối PostgreSQL đồng thời. Luồng tạo đơn/thanh toán/hoàn trên Supabase thật chưa được chạy trong lần rà soát để giữ dữ liệu thật. Gửi thư khôi phục mật khẩu và VNPay chưa được cấu hình; đổi mật khẩu bằng mật khẩu hiện tại và hỗ trợ qua `reset-password.sql` đã có.

Production build và TypeScript đã hoàn tất thành công. Lint không có lỗi; còn 4 cảnh báo `no-img-element` cho ảnh poster/SVG/QR hiện có. Không có lỗi JavaScript trong các lượt kiểm thử trình duyệt.

Đã chạy thêm smoke test bản production với Supabase thật: trang chủ hiển thị đủ 6 phim, trang chi tiết có lịch, khách chưa đăng nhập được chuyển về trang đăng nhập kèm đường dẫn đặt vé, admin bị chặn, URL lạ trả 404 và API chẩn đoán dev bị tắt. Một lần tải đầu gặp lỗi kết nối Supabase tạm thời và đã tải lại thành công; không thay khóa hoặc cấu trúc để xử lý. Lượt smoke cuối không có lỗi JavaScript và không tạo dữ liệu nghiệp vụ.

## Tự kiểm tra lại

```powershell
Set-Location -LiteralPath 'E:\HT\ĐỒ ÁN TỐT NGHIỆP\project'
node scripts/check-setup.mjs
node scripts/tests/reports.mjs
npm.cmd run lint
npm.cmd run build
npm.cmd run dev
```

Mở `http://localhost:3000/cai-dat` khi chạy dev. Database mới dùng `install.sql`; database Chương 3 hiện có dùng `upgrade.sql`. Không reset khi nâng cấp. Nếu chưa có tác vụ Cron, chạy `supabase/enable-expiry-job.sql` bằng SQL Editor; các thao tác đọc/ghi vẫn kiểm tra hết hạn theo giờ máy chủ.
