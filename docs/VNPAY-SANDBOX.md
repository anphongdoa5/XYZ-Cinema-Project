## Triển khai database

Chạy toàn bộ **[supabase/deploy.sql](../supabase/deploy.sql)** một lần trong SQL Editor bằng role postgres.

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


Tài liệu gốc: [Tích hợp VNPay 2.1.0](https://sandbox.vnpayment.vn/apis/docs/thanh-toan-pay/pay.html), [bảng mã lỗi](https://sandbox.vnpayment.vn/apis/docs/bang-ma-loi/), [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys).
