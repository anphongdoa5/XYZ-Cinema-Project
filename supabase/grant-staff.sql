-- Đăng ký khách hàng trên website trước; sửa email và tên đăng nhập dưới đây.
-- Chỉ chạy bằng SQL Editor/DB owner, không qua API công khai.
do $$
declare email_nhan_vien text:='THAY_EMAIL_DA_DANG_KY';ten_dang_nhap text:='nv_quan_tri';
begin
 if email_nhan_vien='THAY_EMAIL_DA_DANG_KY' then raise exception 'Hãy thay THAY_EMAIL_DA_DANG_KY bằng email tài khoản vừa đăng ký.'; end if;
 perform public.cinema_grant_staff(email_nhan_vien,'QUAN_TRI',ten_dang_nhap);
end $$;
-- Đăng nhập nhân viên bằng tên đăng nhập ở trên và mật khẩu tài khoản khách hàng
-- tại thời điểm cấp quyền: http://localhost:3000/admin/login
