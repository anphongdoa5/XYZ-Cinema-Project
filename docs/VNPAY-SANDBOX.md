# VNPay Sandbox và thanh toán mô phỏng

Trang thanh toán cho chọn **Thanh toán mô phỏng** hoặc **VNPay**. Hai luồng dùng chung đơn/ghế và báo cáo; Máy chủ phát hành vé sau khi xác minh IPN, kết quả QueryDr hoặc callback có chữ ký hợp lệ trong sandbox localhost. Mô phỏng vẫn dùng được nếu chưa cấu hình VNPay.

## Triển khai database

Chạy toàn bộ **[supabase/deploy.sql](../supabase/deploy.sql)** một lần trong SQL Editor bằng role postgres. Gói đã gồm VNPay Sandbox, bản sửa xác nhận v2, Tâm điểm, dữ liệu mẫu khi cài mới, admin và Cron. Kết quả cuối là **xyz-cinema-deploy-v1**; cột vnpay_confirmation_v2 là true.

Không cần chạy riêng enable-vnpay.sql hoặc fix-vnpay-confirmation.sql. Các bản vá được giữ làm lịch sử/công cụ bảo trì. Chạy lại deploy.sql trên database Chương 3 được hỗ trợ giữ tài khoản, đơn, ghế, vé, giao dịch và mật khẩu admin. Xem [hướng dẫn triển khai](../HUONG_DAN_CHAY.md).

## Biến môi trường chỉ ở máy chủ

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
SUPABASE_SECRET_KEY=sb_secret_...
APP_URL=http://localhost:3000
VNPAY_TMN_CODE=MA_WEBSITE_DUOC_CAP
VNPAY_HASH_SECRET=KHOA_CHECKSUM_DUOC_CAP
VNPAY_PAYMENT_URL=https://sandbox.vnpayment.vn/paymentv2/vpcpay.html
VNPAY_RETURN_URL=http://localhost:3000/api/payments/vnpay/return
```

`SUPABASE_SECRET_KEY` lấy tại Supabase → Settings → API Keys → Secret keys. Có thể dùng service_role key cũ trong biến này. Không dùng Publishable/anon key cho RPC xác nhận thanh toán, không thêm tiền tố `NEXT_PUBLIC_` cho các khóa bí mật. Khởi động lại `npm run dev` sau khi sửa `.env.local`.

Mỗi người triển khai điền mã website/khóa VNPay Sandbox được cấp vào `.env.local` của mình. Tài liệu và khóa thật không nằm trong mã nguồn hoặc tệp SQL.

## Return URL và IPN URL

- Return: `https://TEN_MIEN_CONG_KHAI/api/payments/vnpay/return`
- IPN: `https://TEN_MIEN_CONG_KHAI/api/payments/vnpay/ipn` (GET)

Để VNPay gửi IPN, ứng dụng phải có địa chỉ HTTPS công khai và IPN được cấu hình cho merchant sandbox trong Merchant Admin/SIT theo tài liệu VNPay. Khi triển khai hoặc dùng tunnel do bạn quản lý, đặt `APP_URL` và `VNPAY_RETURN_URL` theo **cùng tên miền đó**, cập nhật IPN rồi khởi động lại ứng dụng. Không đặt IPN vào `vnp_ReturnUrl`.

Với localhost, máy chủ VNPay không gọi được IPN trên máy cá nhân. Bản sửa cho phép **chỉ trong sandbox localhost** xác nhận từ callback Return có HMAC-SHA512 hợp lệ, merchant đúng và số tiền/mã tham chiếu khớp database. Cả hai mã kết quả và trạng thái phải là 00; số giao dịch, ngày trả tiền, quyền giữ ghế và chống lặp vẫn được kiểm tra trong một giao dịch SQL. Thay đổi này nhằm hỗ trợ thử nghiệm cục bộ. Khi triển khai tên miền công khai, Return không tự cập nhật theo dữ liệu trình duyệt; IPN/QueryDr là nguồn xác nhận. Đây là khác biệt có chủ đích với hướng dẫn VNPay (Return chỉ hiển thị kết quả).

Trang đơn có nút **Kiểm tra lại VNPay** và tự truy vấn một lần khi mở đơn đang chờ/cần đối soát. QueryDr chạy từ máy chủ, lấy thông tin đơn từ database, xác minh chữ ký phản hồi và giới hạn mỗi giao dịch một lần/phút. API trả lỗi 99/timeout/sai chữ ký hoặc sai số tiền không được coi là đã thanh toán. Nếu API sandbox chưa sẵn sàng, ở trang kết quả VNPay bấm quay lại website để gửi callback đã ký. Không tạo chữ ký mới cho kết quả tự khai hoặc lấy ảnh dashboard làm căn cứ tự phát vé.

## Các tình huống xử lý

- Số tiền lấy từ database, nhân 100 khi gửi VNPay; chốt mã ưu đãi trước khi tạo URL. URL dùng HMAC-SHA512, ngày giờ GMT+7, hạn bằng hạn gốc của đơn (10 phút).
- Khi giao dịch VNPay đang chờ, không cho đổi mã hoặc trả tiếp bằng mô phỏng. Có thể bấm **Tiếp tục trên VNPay** để mở lại cùng mã tham chiếu; không gia hạn đơn.
- IPN kiểm tra chữ ký, merchant, mã tham chiếu, số tiền, kết quả và trạng thái giao dịch. Chỉ cặp `00/00` phát vé. Xử lý lặp không tạo thêm khoản thu/vé.
- IPN thất bại/hủy mở lại lựa chọn phương thức nếu đơn còn hạn. Nếu đóng tab VNPay mà không có kết quả IPN, đợi hết hạn đơn để tránh thanh toán hai lần.
- Kết quả thành công đến muộn có thể phục hồi đơn hết hạn nếu thời điểm trả tiền đã được xác minh nằm trong hạn gốc, suất chưa bắt đầu và đúng các ghế cũ còn trống. Ghế đã thuộc đơn khác, đơn đã hủy, suất ngừng hoặc trả sau hạn được giữ ở trạng thái **cần đối soát**; không phát vé sai. Nhân viên thấy mã tham chiếu trong chi tiết đơn để tra cứu tại VNPay Sandbox.
- Đơn 0 đồng dùng thanh toán mô phỏng.
- **Hủy và hoàn tiền hiện vẫn là mô phỏng phục vụ báo cáo. Chưa tích hợp API hoàn tiền VNPay.** Giao diện và lịch sử giao dịch ghi rõ điều này. Nếu cần hoàn giao dịch sandbox tại cổng, xử lý qua công cụ merchant VNPay và đối soát riêng.

## Xác minh

- `npm run build` và ESLint cho các tệp thanh toán.
- `node scripts/tests/vnpay.mjs`: chữ ký, mã hóa, giả mạo tham số và rút gọn mô tả.
- Đã kiểm thử riêng bằng PostgreSQL và trình duyệt: mô phỏng, khởi tạo VNPay, Return localhost có chữ ký / Return tên miền công khai chỉ điều hướng và QueryDr, IPN hợp lệ/sai chữ ký/sai số tiền/lặp/hết hạn, khóa thanh toán kép và nâng cấp SQL giữ dữ liệu.
- Đã kiểm thử hoàn chỉnh bằng thẻ NCB/OTP test chính thức trên VNPay Sandbox và database QA riêng: thanh toán → callback về localhost → đơn đã thanh toán, một khoản thu và đúng một vé. Chưa kiểm thử IPN trên tên miền công khai.

Tài liệu gốc: [Tích hợp VNPay 2.1.0](https://sandbox.vnpayment.vn/apis/docs/thanh-toan-pay/pay.html), [bảng mã lỗi](https://sandbox.vnpayment.vn/apis/docs/bang-ma-loi/), [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys).
