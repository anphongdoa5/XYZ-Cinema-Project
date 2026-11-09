# Khu quản trị và giao diện theo bộ ảnh — 09/11/2026

## Tâm điểm tự động theo số vé bán trong tuần

Chạy **supabase/update-weekly-feature.sql** trong Supabase SQL Editor → New query → dán toàn bộ → Run. Kết quả **weekly-feature-v1**. Không chạy reset.sql hoặc install.sql trên database đang dùng. Tải lại trang chủ sau khi cập nhật. Bản install.sql/upgrade.sql hiện tại đã gồm chức năng này.

- Tuần từ thứ Hai 00:00 đến trước thứ Hai kế tiếp theo Asia/Ho_Chi_Minh. Dùng thời điểm khoản THU thành công, không dùng ngày đặt hoặc ngày chiếu.
- Đếm từng vé của đơn DA_THANH_TOAN, trạng thái vé HIEU_LUC hoặc DA_SU_DUNG. Vé đã hủy, đơn đã hủy/hoàn, giữ ghế, thanh toán chờ/thất bại không được tính. Một vé ghế đôi là một vé, dù có hai chỗ ngồi.
- Phim có số vé lớn nhất được đưa lên Tâm điểm. Đồng hạng ưu tiên mã phim nhỏ hơn; phim ngừng không được chọn. Phim sắp chiếu có vé bán trước vẫn được xét.
- Khi chưa có vé bán trong tuần, giới thiệu phim đang chiếu để khối Tâm điểm không trống. Số vé chỉ xuất hiện khi có vé bán. Trang chủ cập nhật thống kê mỗi 60 giây, không phụ thuộc tab/bộ lọc của khách.
- Chỉ sửa hàm cinema_catalog() để trả tổng vé theo phim và khoảng tuần, không trả đơn/giao dịch/dữ liệu khách cho trang công khai. Giữ nguyên 15 bảng, cột và dữ liệu; không thêm ô tick hoặc cấu hình thủ công.

Đã kiểm tra 16 tình huống chọn phim và PostgreSQL tách biệt: số vé/số đơn, mốc tuần, múi giờ máy chủ, vé dùng/hủy, thanh toán lỗi/lặp, hoàn tiền, ghế đôi và cập nhật lặp giữ dữ liệu. Có thể chạy kiểm tra chọn phim bằng node scripts/tests/featured.mjs.

Thêm 4 kiểm tra trình duyệt đạt: hiển thị phim dẫn đầu và số vé, độc lập bộ lọc, tự đổi sau 60 giây, tuần rỗng giữ phim giới thiệu. Tổng 20 kiểm tra cho thay đổi này; build/TypeScript đạt, lint không có lỗi (4 cảnh báo thẻ ảnh có sẵn). Database thật chỉ được cập nhật sau khi chạy file SQL phía trên; kiểm thử không tạo đơn/vé thật.

## Điều chỉnh sơ đồ ghế và các màn nhập liệu

- Bỏ Loại phòng khỏi bộ lọc, bảng và form. Dưới sơ đồ thiết kế hiển thị chú thích loại Thường, VIP, Đôi (2 chỗ), Lối đi.
- Nhấn để chọn từng ô hoặc kéo một vùng để chọn nhiều ô; kéo từ ô đã chọn để bỏ chọn. Nút Bỏ chọn xóa lựa chọn hiện tại. Hỗ trợ ghế đôi và các ô trống/lối đi; phòng đã có suất vẫn khóa cấu trúc. Trang khách giữ cách chọn ghế từng chỗ và chú thích tình trạng bán vé.
- Footer khách đã bỏ các liên kết Chính sách/Nhân viên; trang `/chinh-sach` đã được gỡ. Mở khu quản trị trực tiếp bằng `/admin`.
- Khối Tâm điểm dùng cách xếp hạng vé bán theo tuần như hướng dẫn phía trên, dùng poster khung 2:3 không cắt ảnh và một nút Chọn suất chiếu. Theo yêu cầu cập nhật, không thêm tick chọn phim hoặc cấu hình database cho Tâm điểm.
- Đăng nhập/đăng ký khi chưa chọn suất không hiển thị poster rỗng hoặc nhãn Chưa giữ ghế · Chưa tạo đơn. Khi có suất đã chọn, thông tin đặt vé vẫn giữ.
- Ngày khởi chiếu, ngày suất, thời gian khuyến mãi, bộ lọc lịch/đơn và ngày báo cáo có nút lịch riêng: chọn tháng/năm/ngày, Hôm nay hoặc nhập thủ công. Esc đóng lịch; trường không bắt buộc có Xóa ngày. Chọn lại ngày khuyến mãi giữ nguyên giờ đã nhập.

Riêng phần thiết kế ghế/lịch/giao diện không cần SQL. Bổ sung xếp hạng Tâm điểm theo vé bán cần chạy update-weekly-feature.sql như hướng dẫn đầu tài liệu.

Đã đạt 14 tình huống trình duyệt trên bản production và PostgreSQL tách biệt: chọn/kéo/bỏ chọn, ghế đôi/ô trống, lưu sơ đồ, khóa phòng đã dùng, nhập/chọn/xóa ngày, giữ giờ khuyến mãi, bộ lọc và màn mobile 390px. Không tạo dữ liệu kiểm thử trên Supabase thật. Build/TypeScript đạt; lint không có lỗi, còn 4 cảnh báo thẻ ảnh. Kết quả 42 tình huống bên dưới thuộc đợt tách admin trước đó.

## Địa chỉ sử dụng

- Website khách hàng: `http://localhost:3000/`.
- Khu nhân viên: `http://localhost:3000/admin`.
- Đăng nhập nhân viên: `http://localhost:3000/admin/login`.
- Các mục quản trị: `/admin/phim`, `/admin/phong-chieu`, `/admin/lich-chieu`, `/admin/don-ve`, `/admin/khuyen-mai`, `/admin/bao-cao`.
- Các địa chỉ `/quan-tri/...` và `/auth/login?staff=1` cũ tự chuyển sang khu mới.

Nếu đã chạy `supabase/create-dev-admin.sql`, đăng nhập nhân viên bằng `admin` / `admin`. Không cần chạy lại install, reset hay upgrade cho lần thay đổi giao diện này. Database vẫn dùng `chapter3-audit-v2` và 15 bảng theo Chương 3.

## Hai phiên đăng nhập độc lập

Khách dùng cookie HttpOnly `xyz_cinema_session`, nhân viên dùng `xyz_cinema_admin_session`. API khách nằm dưới `/api/cinema/`, API nhân viên dưới `/api/admin/`; server đọc đúng cookie của khu tương ứng và kiểm tra lại vai trò bằng database.

Có thể mở trang khách và trang admin trong cùng trình duyệt, đăng nhập hai tài khoản đồng thời. Đăng nhập hoặc đăng xuất một bên không thay đổi phiên của bên còn lại. Phiên nhân viên của bản cũ không tự được dùng lại cho khu mới; đăng nhập lại một lần tại `/admin/login`, phiên khách hiện tại được giữ.

Đưa token khách vào tên cookie admin không cấp quyền nhân viên. Trang admin kiểm tra phía server; API giữ kiểm tra quyền, Origin và RLS/RPC. Chỉ đổi URL hoặc gửi `staff:true` vào API khách không chuyển được vai trò.

## Các màn đã chỉnh theo 33 ảnh cung cấp

| Ảnh tham chiếu | Màn hình hoặc trạng thái tương ứng |
|---|---|
| 01, 02 | Form khách bên trái, thông tin suất đang chọn bên phải; trường mật khẩu có nút hiện/ẩn; giữ đường dẫn quay lại đặt vé |
| 03 | Trang chủ, khối phim nổi bật, hai tab, tìm theo tên/thể loại, danh sách phim đang/sắp chiếu |
| 04 | Poster và thông tin bên trái, nội dung và chọn ngày/suất bên phải; xác nhận suất trước khi chọn ghế |
| 05 | Ba cột: phim, sơ đồ có nhãn hàng và lối đi giữa, tóm tắt ghế; giới hạn 8 đơn vị vẫn kiểm tra ở database |
| 06 | Đồng hồ giữ ghế phía trên, thông tin phim bên trái, tạm tính và xác nhận bên phải; chọn lại/dừng trả ghế |
| 07 | Đồng hồ thanh toán phía trên; ba cột thông tin, mã/phương thức, chi tiết tiền |
| 08 | Vé điện tử xem từng vé, QR theo mã vé thật, nút trước/sau; thông tin thanh toán ở cột bên phải |
| 09 | Lịch sử dạng danh sách–chi tiết, bộ lọc có Áp dụng, đồng hồ đơn chờ, hủy và xem tiền hoàn |
| BC01–BC03, có/không dữ liệu | Tiêu đề theo tab, panel bộ lọc, 5/4/4 chỉ số, biểu đồ và bảng chi tiết; trạng thái rỗng có nút xóa lọc |
| M06–M10 | Bảng quản trị, bộ lọc, nút tạo, phân trang; đơn và vé là hai tab riêng |
| M10 sửa phần trăm/số tiền/lỗi | Hai cột form–tóm tắt, số tiền có dấu phân cách, lỗi ngay dưới trường, giữ dữ liệu khi lỗi |
| P01 | Trang đăng nhập nhân viên riêng, không hiển thị tài khoản khách |
| P08 | Chi tiết đơn với sidebar, khách hàng, giá đã chốt, thu/hoàn, hủy hộ, bảng giao dịch và vé |
| P11 thêm/sửa phim | Thông tin chính/bổ sung bên trái, poster/trailer bên phải; chọn nhiều thể loại, xem trước poster, xác nhận ngừng phim |
| P12 thêm/sửa phòng | Tên/kích thước/trạng thái phía trên; sơ đồ và công cụ bên trái, sức chứa và ô đang chọn bên phải; khóa cấu trúc đã dùng |
| P13 chưa/đã có giao dịch, xung đột | Form và tự tính thời gian/giá; khóa trường theo giao dịch; bảng đối chiếu lịch phòng, lỗi xung đột không xóa dữ liệu nhập |

Giữ Manrope, màu nền `#080B14`, panel `#101521`, viền `#2B3344`, chữ `#F1F1F3`, chữ phụ `#A1ABBE`, vàng `#FCFC65`, đỏ `#F69C9C`, cùng biểu tượng ghế từ thiết kế. Số liệu, tên, ngày và trạng thái trên website lấy từ database; không gán cố định các ví dụ trong ảnh. Các ngày vẫn dùng điều khiển ngày/giờ của trình duyệt, nên định dạng hiển thị theo thiết lập vùng của máy.

Thanh toán và hoàn tiền vẫn là mô phỏng theo yêu cầu. Khu phương thức có nhãn mô phỏng và VNPay chưa mở; chưa có giao dịch VNPay hay thu tiền thật.

## Kiểm tra sau thay đổi

- 18 tình huống tích hợp trên Next.js thật và PostgreSQL riêng: hai phiên/cookie, phân quyền API, đặt vé, khuyến mãi, QR, lịch sử/hủy hộ, CRUD, các trạng thái form/báo cáo và 9 màn mobile 390px.
- 4 tình huống bổ sung: ghép/tách ghế đôi, từ chối chồng lấn và lưu sơ đồ, cookie sai vai trò, Origin và đăng ký nhân viên.
- 3 tình huống số tiền: phần trăm, giảm cố định, giá suất chiếu hiển thị có dấu phân cách và lưu đúng số vào database.
- 10 kiểm tra công thức báo cáo/domain tiếp tục đạt; không sửa công thức doanh thu, thu/hoàn hoặc lấp đầy để khớp số ví dụ.
- 5 kiểm tra định tuyến phiên: tên cookie riêng, phân biệt `/admin` với các tiền tố giống tên, URL quay lại nội bộ và chống lặp trang đăng nhập. Chạy lại bằng `node scripts/tests/sessions.mjs`.
- 2 tình huống điều hướng trong cùng tab: từ khách sang admin rồi Back không lẫn hồ sơ; thoát admin rồi mở lại vẫn giữ phiên khách.

Tổng 42 tình huống trong lần thay đổi này. Bộ kiểm thử chức năng tạo database tách biệt, không tạo đơn/thu/hoàn hay thay tài khoản trên Supabase thật. Đã chụp các màn desktop và mobile để đối chiếu. Không tràn toàn trang ở các màn mobile đã kiểm tra; bảng và sơ đồ rộng cuộn bên trong vùng chứa.

Kiểm tra thêm bản production với Supabase thật: trang khách tải được phim, `admin` / `admin` đăng nhập và mở được danh sách quản trị; cookie admin không đăng nhập vào API khách. Đã đăng xuất phiên kiểm tra sau khi hoàn tất. Build và TypeScript đạt; lint không có lỗi, còn 4 cảnh báo dùng thẻ ảnh `img` cho poster/QR.

Khởi động lại server đang dùng bằng Ctrl+C rồi `npm.cmd run dev`; mở `/admin` để sử dụng khu mới.
