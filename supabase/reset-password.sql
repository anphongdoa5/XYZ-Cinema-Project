-- Khôi phục tài khoản khi chưa có dịch vụ email: chỉ DB owner chạy trong SQL Editor.
-- Sửa ba giá trị; mật khẩu mới được băm, mọi phiên cũ của tài khoản bị thu hồi.
begin;
set local search_path=public,extensions,pg_temp;
do $$
declare email_tai_khoan text:='THAY_EMAIL';mat_khau_moi text:='THAY_MAT_KHAU_MOI';la_nhan_vien boolean:=false;v_id bigint;
begin
 if email_tai_khoan='THAY_EMAIL' or mat_khau_moi='THAY_MAT_KHAU_MOI' or length(mat_khau_moi)<8 or octet_length(mat_khau_moi)>72 then raise exception 'Điền email và mật khẩu mới hợp lệ trước khi Run.'; end if;
 if la_nhan_vien then
  update nhan_vien set mat_khau=crypt(mat_khau_moi,gen_salt('bf',12)) where lower(email)=lower(email_tai_khoan) returning nhan_vien_id into v_id;
  delete from cinema_private.phien_dang_nhap where nhan_vien_id=v_id;
 else
  update khach_hang set mat_khau=crypt(mat_khau_moi,gen_salt('bf',12)) where lower(email)=lower(email_tai_khoan) returning khach_hang_id into v_id;
  delete from cinema_private.phien_dang_nhap where khach_hang_id=v_id;
 end if;
 if v_id is null then raise exception 'Không tìm thấy tài khoản.'; end if;
end $$;
commit;
