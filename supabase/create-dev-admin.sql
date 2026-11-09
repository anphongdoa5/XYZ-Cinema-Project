-- Tài khoản demo theo yêu cầu: admin / admin.
-- Chạy toàn bộ tệp trong Supabase → SQL Editor → New query → Run.
-- Chỉ DB owner thực thi; không thay quy tắc mật khẩu của trang đăng ký.
begin;
set local search_path=public,extensions,pg_temp;
do $$
declare v_id bigint; v_matches integer; v_email text;
begin
 perform pg_advisory_xact_lock(hashtextextended('xyz_cinema_dev_admin',0));
 select count(*) into v_matches from public.nhan_vien where lower(ten_dang_nhap)='admin';
 if v_matches>1 then raise exception 'Có nhiều tài khoản trùng tên admin khi bỏ qua chữ hoa/thường. Dừng để kiểm tra.'; end if;
 select nhan_vien_id into v_id from public.nhan_vien where lower(ten_dang_nhap)='admin' for update;
 if v_id is null then
  insert into public.nhan_vien(ho_ten,email,vai_tro,ten_dang_nhap,mat_khau,trang_thai)
  values('Quản trị viên demo','dev-admin@xyz-cinema.test','QUAN_TRI','admin',crypt('admin',gen_salt('bf',12)),1)
  returning nhan_vien_id into v_id;
 else
  update public.nhan_vien set ten_dang_nhap='admin',vai_tro='QUAN_TRI',mat_khau=crypt('admin',gen_salt('bf',12)),trang_thai=1
  where nhan_vien_id=v_id;
 end if;
 select email into v_email from public.nhan_vien where nhan_vien_id=v_id;
 delete from cinema_private.phien_dang_nhap where nhan_vien_id=v_id;
 delete from cinema_private.gioi_han_dang_nhap where khoa in ('admin:true',lower(v_email)||':true');
end $$;
commit;
select ten_dang_nhap,vai_tro,trang_thai from public.nhan_vien where ten_dang_nhap='admin';
-- Đăng nhập: http://localhost:3000/admin/login
