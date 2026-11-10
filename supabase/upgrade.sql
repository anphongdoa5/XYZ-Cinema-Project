-- XYZ Cinema · Chương 3, Bảng 3.1–3.17.
-- Sinh bằng node scripts/build-database.mjs; nguồn trong supabase/schema/.
-- CẬP NHẬT CHƯƠNG 3: giữ tài khoản, mật khẩu, đơn, vé, thu/hoàn và dữ liệu mẫu.
-- Dán TOÀN BỘ tệp vào SQL Editor rồi Run. Không chạy reset.sql trước tệp này.
begin;
set local search_path=public,extensions,pg_temp;
do $$ begin
 perform pg_advisory_xact_lock(hashtextextended('xyz_cinema_install',0));
 if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=any(array['khach_hang','nhan_vien','the_loai','phim','phim_the_loai','phong_chieu','loai_ghe','ghe','suat_chieu','ghe_suat_chieu','don_dat_ve','ve','khuyen_mai','phuong_thuc_thanh_toan','thanh_toan']) and c.relkind='r')<>15 or to_regclass('cinema_private.cau_hinh') is null then
  raise exception 'Chưa có đủ cấu trúc Chương 3. Dừng cập nhật, không thay đổi dữ liệu. Xem supabase/README.md.';
 end if;
 if not exists(select 1 from cinema_private.cau_hinh where id and schema_version in ('chapter3-custom-auth-v1','chapter3-audit-v2')) then
  raise exception 'Phiên bản database chưa được nhận diện. Dừng cập nhật để kiểm tra.';
 end if;
end $$;
-- Chỉ máy chủ giữ service key được gọi các RPC VNPay. Không thêm bảng nghiệp vụ public.
create table if not exists cinema_private.vnpay_attempt (
 ref varchar(40) primary key,
 don_dat_ve_id bigint not null references public.don_dat_ve(don_dat_ve_id),
 amount numeric(10,0) not null check(amount>0),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null,
 state text not null default 'pending' check(state in ('pending','paid','failed','review')),
 response_code text, transaction_status text, provider_transaction text unique,
 pay_date text, completed_at timestamptz, last_query_at timestamptz
);
alter table cinema_private.vnpay_attempt add column if not exists last_query_at timestamptz;
create index if not exists cinema_vnpay_order on cinema_private.vnpay_attempt(don_dat_ve_id,created_at desc);
revoke all on cinema_private.vnpay_attempt from public,anon,authenticated;


create or replace function public.cinema_check_show() returns trigger language plpgsql set search_path=public,pg_temp as $$
declare duration integer;
begin
 perform 1 from phong_chieu where phong_chieu_id=new.phong_chieu_id for update;
 select thoi_luong into duration from phim where phim_id=new.phim_id;
 if (TG_OP='INSERT' or new.phim_id is distinct from old.phim_id or new.thoi_gian_bat_dau is distinct from old.thoi_gian_bat_dau or new.thoi_gian_ket_thuc is distinct from old.thoi_gian_ket_thuc) and new.thoi_gian_ket_thuc is distinct from new.thoi_gian_bat_dau+make_interval(mins=>duration+15) then
  raise exception 'Giờ kết thúc phải bằng giờ bắt đầu + thời lượng phim + 15 phút quảng cáo.';
 end if;
 if new.trang_thai<>'DA_HUY' and exists(select 1 from suat_chieu s where s.phong_chieu_id=new.phong_chieu_id and s.suat_chieu_id<>new.suat_chieu_id and s.trang_thai<>'DA_HUY'
   and s.thoi_gian_bat_dau<new.thoi_gian_ket_thuc+interval '15 minutes' and s.thoi_gian_ket_thuc+interval '15 minutes'>new.thoi_gian_bat_dau) then
  raise exception 'Lịch chiếu xung đột hoặc chưa đủ 15 phút dọn phòng (IR05).';
 end if;
 return new;
end $$;

create or replace function public.cinema_check_show_seat() returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from ghe g join suat_chieu s on s.phong_chieu_id=g.phong_chieu_id where g.ghe_id=new.ghe_id and s.suat_chieu_id=new.suat_chieu_id) then raise exception 'Ghế không thuộc phòng của suất chiếu.'; end if;
 if new.don_dat_ve_id is not null and exists(select 1 from cinema_private.don_snapshot x where x.don_dat_ve_id=new.don_dat_ve_id and x.suat_chieu_id<>new.suat_chieu_id) then raise exception 'Ghế và đơn không cùng suất chiếu.'; end if;
 return new;
end $$;

create or replace function public.cinema_check_transaction() returns trigger language plpgsql set search_path=public,pg_temp as $$
declare original thanh_toan;
begin
 if new.loai_giao_dich='HOAN' then
  select * into original from thanh_toan where thanh_toan_id=new.giao_dich_goc_id for update;
  if original.thanh_toan_id is null or original.loai_giao_dich<>'THU' or original.trang_thai<>'THANH_CONG' or original.don_dat_ve_id<>new.don_dat_ve_id or original.phuong_thuc_id<>new.phuong_thuc_id or original.so_tien<>new.so_tien then
   raise exception 'Khoản hoàn phải tham chiếu khoản thu thành công cùng đơn, cùng phương thức và hoàn 100%% thực trả.';
  end if;
 end if;
 return new;
end $$;

create or replace function public.cinema_check_ticket() returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
 if new.trang_thai<>'DA_HUY' and not exists(select 1 from ghe_suat_chieu g join don_dat_ve d on d.don_dat_ve_id=g.don_dat_ve_id
   where g.ghe_suat_chieu_id=new.ghe_suat_chieu_id and d.don_dat_ve_id=new.don_dat_ve_id and d.trang_thai='DA_THANH_TOAN' and g.trang_thai='DA_BAN' and g.gia_ban=new.gia_ve) then raise exception 'Vé phải thuộc ghế đã bán của chính đơn đã thanh toán.'; end if;
 new.qr_code:=new.ma_ve;
 return new;
end $$;

create or replace function public.cinema_session_hash() returns text language sql stable set search_path=public,extensions,pg_temp as $$
 select encode(digest(coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-cinema-session',''),'sha256'),'hex')
$$;

create or replace function public.cinema_customer_id() returns bigint language sql stable security definer set search_path=public,extensions,pg_temp as $$
 select k.khach_hang_id from cinema_private.phien_dang_nhap s join khach_hang k using(khach_hang_id) where s.token_hash=cinema_session_hash() and s.het_han>now() and k.trang_thai=1
$$;

create or replace function public.cinema_staff_id() returns bigint language sql stable security definer set search_path=public,extensions,pg_temp as $$
 select n.nhan_vien_id from cinema_private.phien_dang_nhap s join nhan_vien n using(nhan_vien_id) where s.token_hash=cinema_session_hash() and s.het_han>now() and n.trang_thai=1
$$;

create or replace function public.cinema_staff() returns boolean language sql stable security definer set search_path=public,extensions,pg_temp as $$ select cinema_staff_id() is not null $$;

create or replace function public.cinema_customer() returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
begin
 if cinema_customer_id() is null then raise exception 'Vui lòng đăng nhập bằng tài khoản khách hàng đang hoạt động.'; end if;
end $$;

create or replace function public.cinema_profile() returns jsonb language plpgsql stable security definer set search_path=public,extensions,pg_temp as $$
declare result jsonb;
begin
 select jsonb_build_object('id',k.khach_hang_id::text,'full_name',k.ho_ten,'email',k.email,'phone',k.so_dien_thoai,'active',k.trang_thai=1,'role','customer') into result from khach_hang k where k.khach_hang_id=cinema_customer_id();
 if result is null then
  select jsonb_build_object('id',n.nhan_vien_id::text,'full_name',n.ho_ten,'email',n.email,'phone',n.so_dien_thoai,'active',n.trang_thai=1,'role','staff') into result from nhan_vien n where n.nhan_vien_id=cinema_staff_id();
 end if;
 return result;
end $$;

create or replace function public.cinema_new_session(p_customer bigint,p_staff bigint) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare token text:=encode(gen_random_bytes(32),'hex'); expires timestamptz:=now()+interval '7 days';
begin
 delete from cinema_private.phien_dang_nhap where het_han<=now();
 insert into cinema_private.phien_dang_nhap(token_hash,khach_hang_id,nhan_vien_id,het_han) values(encode(digest(token,'sha256'),'hex'),p_customer,p_staff,expires);
 return jsonb_build_object('token',token,'expires_at',expires);
end $$;

create or replace function public.cinema_register(p_name text,p_email text,p_phone text,p_password text) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare customer_id bigint;
begin
 if length(p_password)<8 or octet_length(p_password)>72 then raise exception 'Mật khẩu cần ít nhất 8 ký tự và tối đa 72 byte UTF-8.'; end if;
 if length(trim(p_name)) not between 1 and 100 or length(trim(p_email))>100 or trim(p_email) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or trim(p_phone) !~ '^\+?[0-9]{9,15}$' then raise exception 'Họ tên, email hoặc số điện thoại chưa hợp lệ.'; end if;
 insert into khach_hang(ho_ten,email,so_dien_thoai,mat_khau) values(trim(p_name),lower(trim(p_email)),trim(p_phone),crypt(p_password,gen_salt('bf',12))) returning khach_hang_id into customer_id;
 return cinema_new_session(customer_id,null);
exception when unique_violation then raise exception 'Email hoặc số điện thoại đã được sử dụng.';
end $$;

create or replace function public.cinema_login(p_login text,p_password text,p_staff boolean default false) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare login_key text:=lower(trim(p_login)); row_hash text; account_id bigint; active boolean; limits cinema_private.gioi_han_dang_nhap;
begin
 if length(p_login)>100 or octet_length(p_password)>72 then return jsonb_build_object('error','Thông tin đăng nhập không đúng.'); end if;
 perform pg_advisory_xact_lock(hashtextextended('login:'||login_key||p_staff,0));
 insert into cinema_private.gioi_han_dang_nhap(khoa) values(login_key||':'||p_staff) on conflict do nothing;
 select * into limits from cinema_private.gioi_han_dang_nhap where khoa=login_key||':'||p_staff for update;
 if limits.bat_dau+interval '15 minutes'<=now() then update cinema_private.gioi_han_dang_nhap set so_lan=0,bat_dau=now() where khoa=limits.khoa; limits.so_lan:=0; end if;
 if limits.so_lan>=10 then return jsonb_build_object('error','Đã thử đăng nhập nhiều lần. Vui lòng thử lại sau 15 phút.'); end if;
 if p_staff then select n.nhan_vien_id,n.mat_khau,n.trang_thai=1 into account_id,row_hash,active from nhan_vien n where lower(n.email)=login_key or lower(n.ten_dang_nhap)=login_key order by n.nhan_vien_id limit 1;
 else select k.khach_hang_id,k.mat_khau,k.trang_thai=1 into account_id,row_hash,active from khach_hang k where lower(k.email)=login_key; end if;
 if row_hash is null then select dummy_password_hash into row_hash from cinema_private.cau_hinh where id; end if;
 if crypt(p_password,row_hash) is distinct from row_hash or account_id is null or not coalesce(active,false) then
  update cinema_private.gioi_han_dang_nhap set so_lan=so_lan+1 where khoa=limits.khoa;
  return jsonb_build_object('error','Thông tin đăng nhập không đúng hoặc tài khoản không hoạt động.');
 end if;
 delete from cinema_private.gioi_han_dang_nhap where khoa=limits.khoa;
 return cinema_new_session(case when not p_staff then account_id end,case when p_staff then account_id end);
end $$;

create or replace function public.cinema_logout() returns void language sql security definer set search_path=public,extensions,pg_temp as $$ delete from cinema_private.phien_dang_nhap where token_hash=cinema_session_hash() $$;

create or replace function public.cinema_change_password(p_current text,p_new text) returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare customer_id bigint:=cinema_customer_id(); staff_id bigint:=cinema_staff_id(); stored text;
begin
 if customer_id is null and staff_id is null then raise exception 'Vui lòng đăng nhập để đổi mật khẩu.'; end if;
 if length(p_new)<8 or octet_length(p_new)>72 then raise exception 'Mật khẩu cần ít nhất 8 ký tự và tối đa 72 byte UTF-8.'; end if;
 if customer_id is not null then select mat_khau into stored from khach_hang where khach_hang_id=customer_id for update;
 else select mat_khau into stored from nhan_vien where nhan_vien_id=staff_id for update; end if;
 if crypt(p_current,stored) is distinct from stored then raise exception 'Mật khẩu hiện tại không đúng.'; end if;
 if customer_id is not null then update khach_hang set mat_khau=crypt(p_new,gen_salt('bf',12)) where khach_hang_id=customer_id;
 else update nhan_vien set mat_khau=crypt(p_new,gen_salt('bf',12)) where nhan_vien_id=staff_id; end if;
 delete from cinema_private.phien_dang_nhap where khach_hang_id=customer_id or nhan_vien_id=staff_id;
end $$;

create or replace function public.cinema_grant_staff(p_email text,p_role text default 'NHAN_VIEN',p_username text default null) returns bigint language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare k khach_hang; n_id bigint;
begin
 if p_role not in ('QUAN_TRI','NHAN_VIEN') then raise exception 'Vai trò không hợp lệ.'; end if;
 select * into k from khach_hang where lower(email)=lower(trim(p_email));
 if k.khach_hang_id is null then raise exception 'Hãy đăng ký tài khoản khách hàng trên website trước.'; end if;
 insert into nhan_vien(ho_ten,email,so_dien_thoai,vai_tro,ten_dang_nhap,mat_khau)
 values(k.ho_ten,k.email,k.so_dien_thoai,p_role,coalesce(nullif(trim(p_username),''),'nv_'||k.khach_hang_id),k.mat_khau)
 on conflict(email) do update set vai_tro=excluded.vai_tro,trang_thai=1 returning nhan_vien_id into n_id;
 return n_id;
end $$;

create or replace function public.cinema_expire(p_show bigint) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('show:'||p_show,0));
 update don_dat_ve d set trang_thai='HET_HAN' from cinema_private.don_snapshot x
 where x.don_dat_ve_id=d.don_dat_ve_id and x.suat_chieu_id=p_show and d.trang_thai in ('MOI_TAO','CHO_THANH_TOAN') and d.ngay_dat+interval '10 minutes'<=now();
 update ghe_suat_chieu g set trang_thai='TRONG',don_dat_ve_id=null,khach_giu_id=null,ma_luot_giu=null,thoi_gian_giu_den=null
 where g.suat_chieu_id=p_show and g.trang_thai='GIU' and g.thoi_gian_giu_den<=now()
 and (g.don_dat_ve_id is null or exists(select 1 from don_dat_ve d where d.don_dat_ve_id=g.don_dat_ve_id and d.trang_thai='HET_HAN'));
end $$;

create or replace function public.cinema_pay(p_order bigint,p_expected numeric) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare o don_dat_ve; p khuyen_mai; discount numeric; why text; outcome text; show_id bigint; method_id integer; seats_count integer;
begin
 perform cinema_customer(); select x.suat_chieu_id into show_id from cinema_private.don_snapshot x join don_dat_ve d using(don_dat_ve_id) where d.don_dat_ve_id=p_order and d.khach_hang_id=cinema_customer_id();
 if show_id is null then raise exception 'Không tìm thấy đơn.'; end if;
 perform cinema_expire(show_id); select * into o from don_dat_ve where don_dat_ve_id=p_order for update;
 if o.trang_thai='DA_THANH_TOAN' then return jsonb_build_object('paid',true); end if;
 if o.trang_thai<>'CHO_THANH_TOAN' or o.ngay_dat+interval '10 minutes'<=now() then raise exception 'Đơn đã hết hạn hoặc không thể thanh toán.'; end if;
 if exists(select 1 from cinema_private.vnpay_attempt where don_dat_ve_id=p_order and (state='review' or (state='pending' and expires_at>now()))) then raise exception 'Đang chờ kết quả VNPay hoặc cần đối soát. Vui lòng kiểm tra đơn trước khi thanh toán lại.'; end if;
 if not exists(select 1 from cinema_private.cau_hinh where id and simulation_enabled) then raise exception 'Thanh toán mô phỏng đang tắt.'; end if;
 select phuong_thuc_id into method_id from phuong_thuc_thanh_toan where ten_phuong_thuc='Thanh toán mô phỏng' and trang_thai=1;
 if method_id is null then raise exception 'Phương thức mô phỏng chưa sẵn sàng.'; end if;
 select jsonb_array_length(du_lieu->'order_items') into seats_count from cinema_private.don_snapshot where don_dat_ve_id=p_order;
 if seats_count=0 or (select count(*) from ghe_suat_chieu where don_dat_ve_id=p_order and trang_thai='GIU' and thoi_gian_giu_den>now())<>seats_count then raise exception 'Ghế không còn được giữ cho đơn. Vui lòng kiểm tra lại.'; end if;
 if o.khuyen_mai_id is not null then
  select * into p from khuyen_mai where khuyen_mai_id=o.khuyen_mai_id for update;
  begin discount:=cinema_promo_discount(p,o.tong_tien_goc); exception when others then why:=sqlerrm; discount:=0; end;
  if why is not null or discount<>o.giam_gia then
   if why is not null then update cinema_private.don_snapshot set du_lieu=du_lieu||jsonb_build_object('promotion_code',null) where don_dat_ve_id=p_order; end if;
   update don_dat_ve set khuyen_mai_id=case when why is null then p.khuyen_mai_id else null end,giam_gia=discount,tong_thanh_toan=tong_tien_goc-discount where don_dat_ve_id=p_order;
   return jsonb_build_object('price_changed',true,'total',o.tong_tien_goc-discount,'reason',coalesce(why,'Giá trị khuyến mãi đã thay đổi.'));
  end if;
 end if;
 if p_expected is distinct from o.tong_thanh_toan then return jsonb_build_object('price_changed',true,'total',o.tong_thanh_toan,'reason','Vui lòng xác nhận tổng tiền hiện tại.'); end if;
 select simulation_outcome into outcome from cinema_private.cau_hinh where id;
 if outcome<>'success' then
  insert into thanh_toan(don_dat_ve_id,phuong_thuc_id,ma_giao_dich,so_tien,trang_thai,loai_giao_dich,noi_dung)
  values(p_order,method_id,'SIM-'||gen_random_uuid(),o.tong_thanh_toan,'THAT_BAI','THU',case when outcome='timeout' then 'Quá thời gian phản hồi 30 giây (mô phỏng)' else 'Thanh toán không thành công (mô phỏng)' end);
  return jsonb_build_object('paid',false,'reason',case when outcome='timeout' then 'Thanh toán không thành công do quá thời gian phản hồi.' else 'Thanh toán chưa thành công. Bạn có thể thử lại khi đơn còn hạn.' end);
 end if;
 insert into thanh_toan(don_dat_ve_id,phuong_thuc_id,ma_giao_dich,so_tien,trang_thai,loai_giao_dich,noi_dung)
 values(p_order,method_id,'SIM-'||gen_random_uuid(),o.tong_thanh_toan,'THANH_CONG','THU','Thanh toán mô phỏng');
 update don_dat_ve set trang_thai='DA_THANH_TOAN' where don_dat_ve_id=p_order;
 update cinema_private.don_snapshot set ngay_thanh_toan=now() where don_dat_ve_id=p_order;
 update ghe_suat_chieu set trang_thai='DA_BAN',thoi_gian_giu_den=null where don_dat_ve_id=p_order;
 insert into ve(don_dat_ve_id,ghe_suat_chieu_id,gia_ve,trang_thai) select p_order,ghe_suat_chieu_id,gia_ban,'HIEU_LUC' from ghe_suat_chieu where don_dat_ve_id=p_order;
 return jsonb_build_object('paid',true);
end $$;

create or replace function public.cinema_cancel_internal(p_order bigint) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare o don_dat_ve; payment thanh_toan;
begin
 select * into o from don_dat_ve where don_dat_ve_id=p_order for update;
 if o.trang_thai='DA_THANH_TOAN' then
  select * into payment from thanh_toan where don_dat_ve_id=p_order and loai_giao_dich='THU' and trang_thai='THANH_CONG';
  if payment.thanh_toan_id is null then raise exception 'Không tìm thấy khoản thu để hoàn.'; end if;
  insert into thanh_toan(don_dat_ve_id,phuong_thuc_id,ma_giao_dich,so_tien,trang_thai,loai_giao_dich,giao_dich_goc_id,noi_dung)
  values(p_order,payment.phuong_thuc_id,'REF-'||gen_random_uuid(),payment.so_tien,'THANH_CONG','HOAN',payment.thanh_toan_id,'Hoàn 100% thực trả (mô phỏng)');
  update don_dat_ve set trang_thai='DA_HUY' where don_dat_ve_id=p_order;
  update cinema_private.don_snapshot set ngay_huy=now() where don_dat_ve_id=p_order;
  update ve set trang_thai='DA_HUY' where don_dat_ve_id=p_order;
  update ghe_suat_chieu set trang_thai='TRONG',don_dat_ve_id=null,khach_giu_id=null,ma_luot_giu=null,thoi_gian_giu_den=null where don_dat_ve_id=p_order;
 end if;
end $$;

create or replace function public.cinema_cancel(p_order bigint) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare o don_dat_ve; show_id bigint; starts timestamptz;
begin
 select x.suat_chieu_id into show_id from cinema_private.don_snapshot x join don_dat_ve d using(don_dat_ve_id) where d.don_dat_ve_id=p_order and (d.khach_hang_id=cinema_customer_id() or cinema_staff());
 if show_id is null then raise exception 'Không tìm thấy đơn.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('show:'||show_id,0));
 select * into o from don_dat_ve where don_dat_ve_id=p_order for update;
 if o.trang_thai='DA_HUY' then return jsonb_build_object('cancelled',true,'refund',o.tong_thanh_toan); end if;
 select thoi_gian_bat_dau into starts from suat_chieu where suat_chieu_id=show_id;
 if o.trang_thai<>'DA_THANH_TOAN' or starts<now()+interval '2 hours' then raise exception 'Chỉ có thể hủy đơn đã thanh toán khi còn ít nhất 2 giờ trước giờ chiếu.'; end if;
 if exists(select 1 from ve where don_dat_ve_id=p_order and trang_thai='DA_SU_DUNG') then raise exception 'Không thể hủy đơn có vé đã sử dụng.'; end if;
 perform cinema_cancel_internal(p_order); return jsonb_build_object('cancelled',true,'refund',o.tong_thanh_toan);
end $$;

create or replace function public.cinema_stop_show(p_show bigint,p_expected jsonb) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare impact jsonb; o record;
begin
 if not cinema_staff() then raise exception 'Bạn không có quyền quản trị.'; end if;
 perform cinema_expire(p_show);
 if not exists(select 1 from suat_chieu where suat_chieu_id=p_show) then raise exception 'Không tìm thấy suất chiếu.'; end if;
 select jsonb_build_object('paid',count(*) filter(where d.trang_thai='DA_THANH_TOAN'),'pending',count(*) filter(where d.trang_thai in ('MOI_TAO','CHO_THANH_TOAN')),
 'refund',coalesce(sum(d.tong_thanh_toan) filter(where d.trang_thai='DA_THANH_TOAN'),0),
 'tickets',(select count(*) from ve v join ghe_suat_chieu g using(ghe_suat_chieu_id) where g.suat_chieu_id=p_show and v.trang_thai<>'DA_HUY'),
 'holds',(select count(distinct ma_luot_giu) from ghe_suat_chieu where suat_chieu_id=p_show and trang_thai='GIU' and don_dat_ve_id is null)) into impact
 from don_dat_ve d join cinema_private.don_snapshot x using(don_dat_ve_id) where x.suat_chieu_id=p_show;
 if p_expected is null or p_expected<>impact then return jsonb_build_object('confirm',true,'impact',impact); end if;
 if not exists(select 1 from cinema_private.don_snapshot where suat_chieu_id=p_show) then
  delete from ghe_suat_chieu where suat_chieu_id=p_show; delete from suat_chieu where suat_chieu_id=p_show;
  return jsonb_build_object('deleted',true);
 end if;
 for o in select d.don_dat_ve_id from don_dat_ve d join cinema_private.don_snapshot x using(don_dat_ve_id) where x.suat_chieu_id=p_show and d.trang_thai='DA_THANH_TOAN' order by d.don_dat_ve_id loop perform cinema_cancel_internal(o.don_dat_ve_id); end loop;
 update don_dat_ve d set trang_thai='HET_HAN' from cinema_private.don_snapshot x where x.don_dat_ve_id=d.don_dat_ve_id and x.suat_chieu_id=p_show and d.trang_thai in ('MOI_TAO','CHO_THANH_TOAN');
 update ghe_suat_chieu set trang_thai='TRONG',don_dat_ve_id=null,khach_giu_id=null,ma_luot_giu=null,thoi_gian_giu_den=null where suat_chieu_id=p_show;
 update suat_chieu set trang_thai='DA_HUY' where suat_chieu_id=p_show;
 return jsonb_build_object('stopped',true,'impact',impact);
end $$;

create or replace function public.cinema_expire_all() returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare s record;
begin
 for s in select distinct suat_chieu_id from ghe_suat_chieu where trang_thai='GIU' and thoi_gian_giu_den<=now() order by suat_chieu_id loop perform cinema_expire(s.suat_chieu_id); end loop;
 delete from cinema_private.phien_dang_nhap where het_han<=now();
 delete from cinema_private.gioi_han_dang_nhap where bat_dau<now()-interval '1 day';
end $$;

create or replace function public.cinema_seat_json(p_seat bigint) returns jsonb language sql stable set search_path=public,pg_temp as $$
 select jsonb_build_object('id',g.ghe_id::text,'room_id',g.phong_chieu_id::text,
 'label',g.hang_ghe||case when l.ten_loai_ghe='Đôi' then g.so_ghe||'-'||(g.so_ghe+1) else g.so_ghe::text end,
 'row_no',ascii(g.hang_ghe)-64,'col_no',g.so_ghe,'kind',case l.ten_loai_ghe when 'VIP' then 'vip' when 'Đôi' then 'couple' else 'standard' end)
 from ghe g join loai_ghe l using(loai_ghe_id) where g.ghe_id=p_seat
$$;

create or replace function public.cinema_seatmap(p_show bigint) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
 perform cinema_expire(p_show);
 if not exists(select 1 from suat_chieu s join phim p using(phim_id) where s.suat_chieu_id=p_show and p.trang_thai<>'NGUNG_CHIEU') and not cinema_staff() then raise exception 'Không tìm thấy suất chiếu.'; end if;
 select jsonb_build_object('server_now',now(),'seats',coalesce(jsonb_agg(cinema_seat_json(g.ghe_id)||jsonb_build_object(
 'status',case g.trang_thai when 'TRONG' then 'available' when 'GIU' then 'held' when 'KHOA' then 'blocked' else 'sold' end,
 'mine',coalesce(g.khach_giu_id=cinema_customer_id() or d.khach_hang_id=cinema_customer_id(),false),
 'own_hold',case when g.khach_giu_id=cinema_customer_id() then g.ma_luot_giu else null end,'expires_at',g.thoi_gian_giu_den)
 order by g.ghe_id),'[]'::jsonb)) into result from ghe_suat_chieu g left join don_dat_ve d using(don_dat_ve_id) where g.suat_chieu_id=p_show;
 return result;
end $$;

create or replace function public.cinema_hold(p_show bigint,p_seats bigint[]) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare s suat_chieu; v_hold text:=gen_random_uuid()::text; v_until timestamptz:=now()+interval '10 minutes'; v_total numeric; customer_id bigint;
begin
 perform cinema_customer(); customer_id:=cinema_customer_id(); perform cinema_expire(p_show);
 select * into s from suat_chieu where suat_chieu_id=p_show;
 if s.suat_chieu_id is null or s.trang_thai<>'DANG_MO_BAN' or s.thoi_gian_bat_dau<=now()+interval '15 minutes'
 or not exists(select 1 from phim where phim_id=s.phim_id and trang_thai<>'NGUNG_CHIEU') or not exists(select 1 from phong_chieu where phong_chieu_id=s.phong_chieu_id and trang_thai=1) then raise exception 'Suất chiếu đã đóng bán hoặc không còn khả dụng.'; end if;
 if coalesce(cardinality(p_seats),0) not between 1 and 8 or cardinality(p_seats)<>(select count(distinct x) from unnest(p_seats) x) then raise exception 'Vui lòng chọn từ 1 đến 8 đơn vị ghế khác nhau.'; end if;
 perform 1 from ghe_suat_chieu where suat_chieu_id=p_show and ghe_id=any(p_seats) order by ghe_id for update;
 if (select count(*) from ghe_suat_chieu x join ghe g using(ghe_id) where x.suat_chieu_id=p_show and x.ghe_id=any(p_seats) and x.trang_thai='TRONG' and g.trang_thai=1)<>cardinality(p_seats) then raise exception 'Một số ghế vừa được người khác giữ. Vui lòng chọn lại.'; end if;
 if exists(select 1 from ghe_suat_chieu where suat_chieu_id=p_show and trang_thai='GIU' and khach_giu_id=customer_id) then raise exception 'Bạn đang có phiên giữ ghế. Hãy tiếp tục hoặc trả ghế trước khi chọn lại.'; end if;
 update ghe_suat_chieu x set trang_thai='GIU',khach_giu_id=customer_id,ma_luot_giu=v_hold,thoi_gian_giu_den=v_until,gia_ban=floor(s.gia_ve_co_ban*l.he_so_gia)
 from ghe g join loai_ghe l using(loai_ghe_id) where x.ghe_id=g.ghe_id and x.suat_chieu_id=p_show and x.ghe_id=any(p_seats);
 select sum(gia_ban) into v_total from ghe_suat_chieu where ma_luot_giu=v_hold;
 if v_total>99999999 then raise exception 'Tổng tiền vượt giới hạn 99.999.999 đồng. Vui lòng giảm số ghế hoặc chọn suất khác.'; end if;
 return jsonb_build_object('id',v_hold,'expires_at',v_until,'quoted_total',v_total,'server_now',now());
end $$;

create or replace function public.cinema_release(p_hold text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare show_id bigint;
begin
 perform cinema_customer(); select suat_chieu_id into show_id from ghe_suat_chieu where ma_luot_giu=p_hold and khach_giu_id=cinema_customer_id() limit 1;
 if show_id is null then raise exception 'Không tìm thấy phiên giữ ghế.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('show:'||show_id,0));
 update ghe_suat_chieu set trang_thai='TRONG',khach_giu_id=null,ma_luot_giu=null,thoi_gian_giu_den=null where ma_luot_giu=p_hold and khach_giu_id=cinema_customer_id() and don_dat_ve_id is null;
end $$;

create or replace function public.cinema_order(p_hold text,p_expected numeric) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare s suat_chieu; show_id bigint; v_id bigint; old_id bigint; total numeric; quoted numeric; items jsonb; detail jsonb;
begin
 perform cinema_customer();
 select x.don_dat_ve_id into old_id from cinema_private.don_snapshot x join don_dat_ve d using(don_dat_ve_id) where x.ma_luot_giu=p_hold and d.khach_hang_id=cinema_customer_id();
 if old_id is not null then return jsonb_build_object('id',old_id::text); end if;
 select suat_chieu_id into show_id from ghe_suat_chieu where ma_luot_giu=p_hold and khach_giu_id=cinema_customer_id() limit 1;
 if show_id is null then raise exception 'Không tìm thấy phiên giữ ghế hoặc đã hết hạn.'; end if;
 perform cinema_expire(show_id);
 -- Sau khóa, kiểm tra lại để hai yêu cầu xác nhận lặp trả cùng một đơn.
 select x.don_dat_ve_id into old_id from cinema_private.don_snapshot x join don_dat_ve d using(don_dat_ve_id) where x.ma_luot_giu=p_hold and d.khach_hang_id=cinema_customer_id();
 if old_id is not null then return jsonb_build_object('id',old_id::text); end if;
 if not exists(select 1 from ghe_suat_chieu where ma_luot_giu=p_hold and khach_giu_id=cinema_customer_id() and trang_thai='GIU' and thoi_gian_giu_den>now()) then raise exception 'Đã hết thời gian giữ ghế. Vui lòng chọn lại.'; end if;
 select * into s from suat_chieu where suat_chieu_id=show_id;
 if s.trang_thai='DA_HUY' then raise exception 'Suất chiếu đã ngừng.'; end if;
 select sum(floor(s.gia_ve_co_ban*l.he_so_gia)),sum(x.gia_ban) into total,quoted from ghe_suat_chieu x join ghe g using(ghe_id) join loai_ghe l using(loai_ghe_id) where x.ma_luot_giu=p_hold;
 if total>99999999 then raise exception 'Tổng tiền vượt giới hạn 99.999.999 đồng.'; end if;
 if total is distinct from p_expected then return jsonb_build_object('price_changed',true,'total',total); end if;
 insert into don_dat_ve(khach_hang_id,tong_tien_goc,tong_thanh_toan,trang_thai) values(cinema_customer_id(),total,total,'CHO_THANH_TOAN') returning don_dat_ve_id into v_id;
 update ghe_suat_chieu x set gia_ban=floor(s.gia_ve_co_ban*l.he_so_gia) from ghe g join loai_ghe l using(loai_ghe_id) where x.ghe_id=g.ghe_id and x.ma_luot_giu=p_hold;
 select jsonb_agg(cinema_seat_json(x.ghe_id)||jsonb_build_object('id',x.ghe_suat_chieu_id::text,'seat_id',x.ghe_id::text,'price',x.gia_ban) order by x.ghe_id) into items from ghe_suat_chieu x where x.ma_luot_giu=p_hold;
 select jsonb_build_object('movie_title',p.ten_phim,'room_name',r.ten_phong,'show_starts_at',s.thoi_gian_bat_dau,'show_format',concat_ws(' ',s.dinh_dang_chieu,s.ngon_ngu_hien_thi),'order_items',items) into detail from phim p,phong_chieu r where p.phim_id=s.phim_id and r.phong_chieu_id=s.phong_chieu_id;
 insert into cinema_private.don_snapshot(don_dat_ve_id,suat_chieu_id,ma_luot_giu,du_lieu) values(v_id,show_id,p_hold,detail);
 -- IR07: khi đã có đơn, xóa chủ/mã lượt giữ, thay bằng FK đến đơn.
 update ghe_suat_chieu set don_dat_ve_id=v_id,khach_giu_id=null,ma_luot_giu=null,thoi_gian_giu_den=now()+interval '10 minutes' where ma_luot_giu=p_hold;
 return jsonb_build_object('id',v_id::text);
end $$;

create or replace function public.cinema_promo_discount(p khuyen_mai,p_subtotal numeric) returns numeric language plpgsql set search_path=public,pg_temp as $$
declare used integer; discount numeric;
begin
 if p.khuyen_mai_id is null then raise exception 'Mã khuyến mãi không hợp lệ.'; end if;
 if p.trang_thai<>1 then raise exception 'Chương trình đang tạm dừng hoặc đã ngừng.'; end if;
 if p.ngay_bat_dau>now() then raise exception 'Chương trình chưa bắt đầu.'; end if;
 if p.ngay_ket_thuc<now() then raise exception 'Mã khuyến mãi đã hết hạn.'; end if;
 select count(distinct d.don_dat_ve_id) into used from don_dat_ve d join thanh_toan t using(don_dat_ve_id) where d.khuyen_mai_id=p.khuyen_mai_id and t.loai_giao_dich='THU' and t.trang_thai='THANH_CONG';
 -- VNPay đã chốt giá: giữ lượt ưu đãi đến khi có kết quả hoặc hết hạn.
 select used+count(*) into used from cinema_private.vnpay_attempt a join don_dat_ve d using(don_dat_ve_id)
 where d.khuyen_mai_id=p.khuyen_mai_id and a.state='pending' and a.expires_at>now();
 if p.so_luong_toi_da is not null and used>=p.so_luong_toi_da then raise exception 'Mã khuyến mãi đã hết lượt sử dụng.'; end if;
 if p_subtotal<coalesce(p.dieu_kien_ap_dung,0) then raise exception 'Đơn chưa đạt mức tối thiểu % đồng.',p.dieu_kien_ap_dung; end if;
 discount:=case when p.hinh_thuc_giam='SO_TIEN' then p.gia_tri_giam else floor(p_subtotal*p.gia_tri_giam/100) end;
 if p.hinh_thuc_giam='PHAN_TRAM' and p.giam_toi_da is not null then discount:=least(discount,p.giam_toi_da); end if;
 return least(p_subtotal,floor(discount));
end $$;

create or replace function public.cinema_promo(p_order bigint,p_code text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare o don_dat_ve; p khuyen_mai; discount numeric:=0; show_id bigint;
begin
 perform cinema_customer(); select x.suat_chieu_id into show_id from cinema_private.don_snapshot x join don_dat_ve d using(don_dat_ve_id) where d.don_dat_ve_id=p_order and d.khach_hang_id=cinema_customer_id();
 if show_id is null then raise exception 'Không tìm thấy đơn.'; end if;
 perform cinema_expire(show_id); select * into o from don_dat_ve where don_dat_ve_id=p_order for update;
 if o.trang_thai<>'CHO_THANH_TOAN' or o.ngay_dat+interval '10 minutes'<=now() then raise exception 'Đơn không còn trong thời hạn thanh toán.'; end if;
 if exists(select 1 from cinema_private.vnpay_attempt where don_dat_ve_id=p_order and (state='review' or (state='pending' and expires_at>now()))) then raise exception 'Đang chờ kết quả VNPay hoặc cần đối soát. Vui lòng kiểm tra đơn trước khi thanh toán lại.'; end if;
 if trim(coalesce(p_code,''))<>'' then select * into p from khuyen_mai where ma_khuyen_mai=upper(trim(p_code)); discount:=cinema_promo_discount(p,o.tong_tien_goc); end if;
 update don_dat_ve set khuyen_mai_id=p.khuyen_mai_id,giam_gia=discount,tong_thanh_toan=tong_tien_goc-discount where don_dat_ve_id=p_order;
 update cinema_private.don_snapshot set du_lieu=du_lieu||jsonb_build_object('promotion_code',p.ma_khuyen_mai) where don_dat_ve_id=p_order;
 return jsonb_build_object('total',o.tong_tien_goc-discount,'discount',discount);
end $$;

create or replace function public.cinema_catalog() returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
 -- Tuần ISO: thứ Hai 00:00 đến thứ Hai kế tiếp, theo giờ Việt Nam.
 with week_window as (
  select date_trunc('week',now() at time zone 'Asia/Ho_Chi_Minh') at time zone 'Asia/Ho_Chi_Minh' as starts_at,
   (date_trunc('week',now() at time zone 'Asia/Ho_Chi_Minh')+interval '1 week') at time zone 'Asia/Ho_Chi_Minh' as ends_at
 ), weekly_sales as (
  select s.phim_id,count(*) as tickets_sold
  from ve v join don_dat_ve d using(don_dat_ve_id)
  join ghe_suat_chieu g using(ghe_suat_chieu_id) join suat_chieu s using(suat_chieu_id)
  cross join week_window w
  where d.trang_thai='DA_THANH_TOAN' and v.trang_thai in ('HIEU_LUC','DA_SU_DUNG')
   and exists(select 1 from thanh_toan t where t.don_dat_ve_id=d.don_dat_ve_id
    and t.loai_giao_dich='THU' and t.trang_thai='THANH_CONG'
    and t.thoi_gian_thanh_toan>=w.starts_at and t.thoi_gian_thanh_toan<w.ends_at)
  group by s.phim_id
 )
 select jsonb_build_object('server_now',now(),
 'weekly_sales_period',(select jsonb_build_object('starts_at',starts_at,'ends_at',ends_at,'timezone','Asia/Ho_Chi_Minh') from week_window),
 'movies',coalesce((select jsonb_agg(jsonb_build_object('id',p.phim_id::text,'title',p.ten_phim,'duration',p.thoi_luong,
   'genres',coalesce((select string_agg(t.ten_the_loai,', ' order by t.ten_the_loai) from phim_the_loai pt join the_loai t using(the_loai_id) where pt.phim_id=p.phim_id),''),
   'age',case when coalesce(p.do_tuoi_gioi_han,0)=0 then 'P' else 'C'||p.do_tuoi_gioi_han end,'language',coalesce(p.ngon_ngu,''),
   'description',coalesce(p.mo_ta,''),'poster_url',coalesce(p.poster_url,''),'trailer_url',coalesce((select trailer_url from cinema_private.phim_hien_thi h where h.phim_id=p.phim_id),''),
   'weekly_tickets_sold',coalesce(ws.tickets_sold,0),
   'director',coalesce(p.dao_dien,''),'actors',coalesce(p.dien_vien,''),'country',coalesce(p.quoc_gia,''),'release_date',p.ngay_khoi_chieu,
   'status',case p.trang_thai when 'DANG_CHIEU' then 'showing' when 'SAP_CHIEU' then 'coming' else 'stopped' end) order by p.phim_id)
   from phim p left join weekly_sales ws on ws.phim_id=p.phim_id where cinema_staff() or p.trang_thai<>'NGUNG_CHIEU'),'[]'::jsonb),
 'rooms',coalesce((select jsonb_agg(jsonb_build_object('id',r.phong_chieu_id::text,'name',r.ten_phong,'capacity',r.suc_chua,'format','',
   'status',case r.trang_thai when 1 then 'active' else 'maintenance' end) order by r.phong_chieu_id) from phong_chieu r),'[]'::jsonb),
 'showtimes',coalesce((select jsonb_agg(jsonb_build_object('id',s.suat_chieu_id::text,'movie_id',s.phim_id::text,'room_id',s.phong_chieu_id::text,
   'starts_at',s.thoi_gian_bat_dau,'ends_at',s.thoi_gian_ket_thuc,'base_price',s.gia_ve_co_ban,'format',concat_ws(' ',s.dinh_dang_chieu,s.ngon_ngu_hien_thi),
   'status',case s.trang_thai when 'DANG_MO_BAN' then 'open' when 'DA_HUY' then 'stopped' else 'closed' end) order by s.thoi_gian_bat_dau)
   from suat_chieu s join phim p using(phim_id) where cinema_staff() or (s.trang_thai<>'DA_HUY' and p.trang_thai<>'NGUNG_CHIEU' and s.thoi_gian_bat_dau>now())),'[]'::jsonb)) into result;
 return result;
end $$;

create or replace function public.cinema_order_json(p_order bigint) returns jsonb language sql stable set search_path=public,pg_temp as $$
 select x.du_lieu||jsonb_build_object('id',d.don_dat_ve_id::text,'code',d.ma_don,'user_id',d.khach_hang_id::text,'showtime_id',x.suat_chieu_id::text,'hold_id',x.ma_luot_giu,
 'status',case d.trang_thai when 'DA_THANH_TOAN' then 'paid' when 'DA_HUY' then 'cancelled' when 'HET_HAN' then 'expired' else 'pending' end,
 'subtotal',d.tong_tien_goc,'discount',d.giam_gia,'total',d.tong_thanh_toan,'promotion_id',d.khuyen_mai_id::text,'promotion_code',case when x.du_lieu ? 'promotion_code' then x.du_lieu->>'promotion_code' else p.ma_khuyen_mai end,
 'created_at',d.ngay_dat,'expires_at',d.ngay_dat+interval '10 minutes','paid_at',x.ngay_thanh_toan,'cancelled_at',x.ngay_huy,
 'vnpay', (select jsonb_build_object('state',a.state,'response_code',a.response_code,'ref',a.ref) from cinema_private.vnpay_attempt a where a.don_dat_ve_id=d.don_dat_ve_id order by a.created_at desc limit 1),
 'tickets',coalesce((select jsonb_agg(jsonb_build_object('id',v.ve_id::text,'seat_id',g.ghe_id::text,'code',v.ma_ve,'qr_token',v.ma_ve,'issued_at',v.thoi_gian_xuat,
   'status',case v.trang_thai when 'HIEU_LUC' then 'valid' when 'DA_SU_DUNG' then 'used' else 'cancelled' end) order by v.ve_id)
   from ve v join ghe_suat_chieu g using(ghe_suat_chieu_id) where v.don_dat_ve_id=d.don_dat_ve_id),'[]'::jsonb),
 'transactions',coalesce((select jsonb_agg(jsonb_build_object('id',t.thanh_toan_id::text,'order_id',t.don_dat_ve_id::text,
   'kind',case t.loai_giao_dich when 'THU' then 'payment' else 'refund' end,'result',case t.trang_thai when 'THANH_CONG' then 'success' when 'THAT_BAI' then 'failed' else 'pending' end,
   'amount',t.so_tien,'method',case when m.ten_phuong_thuc='Thanh toán mô phỏng' then 'simulation' else m.ten_phuong_thuc end,'reason',t.noi_dung,'created_at',t.thoi_gian_thanh_toan,
   'original_id',t.giao_dich_goc_id::text) order by t.thanh_toan_id) from thanh_toan t join phuong_thuc_thanh_toan m using(phuong_thuc_id) where t.don_dat_ve_id=d.don_dat_ve_id),'[]'::jsonb))
 from don_dat_ve d join cinema_private.don_snapshot x using(don_dat_ve_id) left join khuyen_mai p using(khuyen_mai_id) where d.don_dat_ve_id=p_order
$$;

create or replace function public.cinema_orders(p_order bigint default null) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare s record; result jsonb;
begin
 if cinema_customer_id() is null and not cinema_staff() then raise exception 'Vui lòng đăng nhập để tiếp tục.'; end if;
 for s in select distinct x.suat_chieu_id from cinema_private.don_snapshot x join don_dat_ve d using(don_dat_ve_id)
  where (cinema_staff() or d.khach_hang_id=cinema_customer_id()) and (p_order is null or d.don_dat_ve_id=p_order) and d.trang_thai in ('MOI_TAO','CHO_THANH_TOAN') and d.ngay_dat+interval '10 minutes'<=now() order by x.suat_chieu_id
 loop perform cinema_expire(s.suat_chieu_id); end loop;
 select jsonb_build_object('server_now',now(),'orders',coalesce(jsonb_agg(cinema_order_json(d.don_dat_ve_id) order by d.ngay_dat desc),'[]'::jsonb)) into result from don_dat_ve d
 where (cinema_staff() or d.khach_hang_id=cinema_customer_id()) and (p_order is null or d.don_dat_ve_id=p_order);
 return result;
end $$;

create or replace function public.cinema_hold_details(p_hold text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare show_id bigint; result jsonb;
begin
 perform cinema_customer();
 select suat_chieu_id into show_id from ghe_suat_chieu where ma_luot_giu=p_hold and khach_giu_id=cinema_customer_id() limit 1;
 if show_id is null then
  select jsonb_build_object('id',p_hold,'showtime_id',x.suat_chieu_id::text,'status','converted','expires_at',d.ngay_dat,'quoted_total',d.tong_tien_goc,'server_now',now(),'seats','[]'::jsonb) into result
  from cinema_private.don_snapshot x join don_dat_ve d using(don_dat_ve_id) where x.ma_luot_giu=p_hold and d.khach_hang_id=cinema_customer_id();
  if result is null then raise exception 'Phiên giữ ghế không tồn tại hoặc đã hết hạn.'; end if;
  return result;
 end if;
 perform cinema_expire(show_id);
 select jsonb_build_object('id',p_hold,'showtime_id',show_id::text,'status',case when count(*)>0 then 'active' else 'expired' end,
 'expires_at',coalesce(min(thoi_gian_giu_den),now()),'quoted_total',coalesce(sum(gia_ban),0),'server_now',now(),
 'seats',coalesce(jsonb_agg(cinema_seat_json(ghe_id) order by ghe_id),'[]'::jsonb)) into result
 from ghe_suat_chieu where ma_luot_giu=p_hold and khach_giu_id=cinema_customer_id();
 return result;
end $$;

create or replace function public.cinema_reservation(p_show bigint) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform cinema_customer(); perform cinema_expire(p_show);
 return jsonb_build_object('holdId',(select ma_luot_giu from ghe_suat_chieu where suat_chieu_id=p_show and khach_giu_id=cinema_customer_id() and trang_thai='GIU' order by thoi_gian_giu_den desc limit 1),
 'orderId',(select d.don_dat_ve_id::text from don_dat_ve d join cinema_private.don_snapshot x using(don_dat_ve_id) where x.suat_chieu_id=p_show and d.khach_hang_id=cinema_customer_id() and d.trang_thai='CHO_THANH_TOAN' and d.ngay_dat+interval '10 minutes'>now() order by d.ngay_dat desc limit 1),'server_now',now());
end $$;

create or replace function public.cinema_admin() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
 if not cinema_staff() then raise exception 'Bạn không có quyền quản trị.'; end if;
 perform cinema_expire_all(); result:=cinema_catalog();
 return result||jsonb_build_object('seats',coalesce((select jsonb_agg(cinema_seat_json(ghe_id) order by ghe_id) from ghe),'[]'::jsonb),
 'orders',(cinema_orders()->'orders'),
 'profiles',coalesce((select jsonb_agg(jsonb_build_object('id',k.khach_hang_id::text,'full_name',k.ho_ten,'email',k.email,'phone',k.so_dien_thoai,'role','customer','active',k.trang_thai=1) order by k.khach_hang_id) from khach_hang k),'[]'::jsonb),
 'promotions',coalesce((select jsonb_agg(jsonb_build_object('id',p.khuyen_mai_id::text,'code',p.ma_khuyen_mai,'name',p.ten_khuyen_mai,
   'kind',case p.hinh_thuc_giam when 'PHAN_TRAM' then 'percent' else 'fixed' end,'value',p.gia_tri_giam,'max_discount',p.giam_toi_da,'min_order',coalesce(p.dieu_kien_ap_dung,0),
   'starts_at',p.ngay_bat_dau,'ends_at',p.ngay_ket_thuc,'max_uses',p.so_luong_toi_da,
   'used_count',(select count(distinct d.don_dat_ve_id) from don_dat_ve d join thanh_toan t using(don_dat_ve_id) where d.khuyen_mai_id=p.khuyen_mai_id and t.loai_giao_dich='THU' and t.trang_thai='THANH_CONG'),
   'status',case p.trang_thai when 1 then 'active' when 2 then 'paused' else 'stopped' end) order by p.khuyen_mai_id) from khuyen_mai p),'[]'::jsonb),
 'inventory',coalesce((select jsonb_agg(jsonb_build_object('showtime_id',g.suat_chieu_id::text,'seat_id',g.ghe_id::text,'expires_at',g.thoi_gian_giu_den,
   'status',case g.trang_thai when 'TRONG' then 'available' when 'GIU' then 'held' when 'KHOA' then 'blocked' else 'sold' end) order by g.suat_chieu_id,g.ghe_id) from ghe_suat_chieu g),'[]'::jsonb));
end $$;

create or replace function public.cinema_version() returns text language sql stable security definer set search_path=public,pg_temp as $$ select schema_version from cinema_private.cau_hinh where id $$;

create or replace function public.cinema_admin_save(p_entity text,p_data jsonb) returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id bigint:=nullif(p_data->>'id','')::bigint; old_movie phim; old_room phong_chieu; old_show suat_chieu; old_promo khuyen_mai;
 movie_row phim; room_id integer; start_time timestamptz; end_time timestamptz; busy boolean; x jsonb; genre text; capacity integer; used integer;
begin
 if not cinema_staff() then raise exception 'Bạn không có quyền quản trị.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('cinema_catalog',0));
 if p_entity='movies' then
  select * into old_movie from phim where phim_id=v_id;
  if old_movie.phim_id is not null and (old_movie.thoi_luong<>(p_data->>'duration')::integer or (p_data->>'status'='stopped' and old_movie.trang_thai<>'NGUNG_CHIEU'))
   and exists(select 1 from suat_chieu where phim_id=v_id and thoi_gian_bat_dau>now() and trang_thai<>'DA_HUY') then raise exception 'Hãy xử lý các suất tương lai trước khi đổi thời lượng hoặc ngừng phim.'; end if;
  if nullif(trim(p_data->>'genres'),'') is null then raise exception 'Vui lòng chọn ít nhất một thể loại.'; end if;
  v_id:=coalesce(v_id,nextval(pg_get_serial_sequence('public.phim','phim_id')));
  insert into phim(phim_id,ten_phim,thoi_luong,do_tuoi_gioi_han,dao_dien,dien_vien,quoc_gia,ngon_ngu,ngay_khoi_chieu,mo_ta,poster_url,trang_thai)
  values(v_id,trim(p_data->>'title'),(p_data->>'duration')::integer,case when p_data->>'age'='P' then 0 else replace(p_data->>'age','C','')::integer end,
  p_data->>'director',p_data->>'actors',p_data->>'country',p_data->>'language',nullif(p_data->>'release_date','')::date,p_data->>'description',p_data->>'poster_url',
  case p_data->>'status' when 'showing' then 'DANG_CHIEU' when 'coming' then 'SAP_CHIEU' when 'stopped' then 'NGUNG_CHIEU' else p_data->>'status' end)
  on conflict(phim_id) do update set ten_phim=excluded.ten_phim,thoi_luong=excluded.thoi_luong,do_tuoi_gioi_han=excluded.do_tuoi_gioi_han,dao_dien=excluded.dao_dien,dien_vien=excluded.dien_vien,quoc_gia=excluded.quoc_gia,
  ngon_ngu=excluded.ngon_ngu,ngay_khoi_chieu=excluded.ngay_khoi_chieu,mo_ta=excluded.mo_ta,poster_url=excluded.poster_url,trang_thai=excluded.trang_thai;
  delete from phim_the_loai where phim_id=v_id;
  insert into cinema_private.phim_hien_thi(phim_id,trailer_url) values(v_id,coalesce(p_data->>'trailer_url','')) on conflict(phim_id) do update set trailer_url=excluded.trailer_url;
  for genre in select distinct trim(value) from regexp_split_to_table(p_data->>'genres',',') value where trim(value)<>'' loop
   insert into the_loai(ten_the_loai) values(genre) on conflict(ten_the_loai) do nothing;
   insert into phim_the_loai(phim_id,the_loai_id) select v_id,the_loai_id from the_loai where ten_the_loai=genre;
  end loop;
 elsif p_entity='rooms' then
  select * into old_room from phong_chieu where phong_chieu_id=v_id;
  busy:=exists(select 1 from suat_chieu where phong_chieu_id=v_id);
  if busy and ((p_data ? 'seats') or (old_room.trang_thai=1 and p_data->>'status'='maintenance' and exists(select 1 from suat_chieu where phong_chieu_id=v_id and thoi_gian_bat_dau>now() and trang_thai<>'DA_HUY'))) then raise exception 'Phòng đã có suất chiếu. Không thể đổi sơ đồ; hãy xử lý suất trước khi bảo trì.'; end if;
  if old_room.phong_chieu_id is null and not (p_data ? 'seats') then raise exception 'Phòng mới cần có sơ đồ ghế.'; end if;
  capacity:=old_room.suc_chua;
  if p_data ? 'seats' then
   if jsonb_array_length(p_data->'seats') not between 1 and 600 then raise exception 'Sơ đồ cần từ 1 đến 600 đơn vị ghế.'; end if;
   select sum(case when value->>'kind'='couple' then 2 else 1 end) into capacity from jsonb_array_elements(p_data->'seats');
  end if;
  v_id:=coalesce(v_id,nextval(pg_get_serial_sequence('public.phong_chieu','phong_chieu_id')));
  insert into phong_chieu(phong_chieu_id,ten_phong,suc_chua,trang_thai) values(v_id,trim(p_data->>'name'),capacity,case p_data->>'status' when 'active' then 1 when 'maintenance' then 0 else null end)
  on conflict(phong_chieu_id) do update set ten_phong=excluded.ten_phong,suc_chua=excluded.suc_chua,trang_thai=excluded.trang_thai;
  if p_data ? 'seats' then
   delete from ghe where phong_chieu_id=v_id;
   for x in select value from jsonb_array_elements(p_data->'seats') loop
    if x->>'kind' not in ('standard','vip','couple') then raise exception 'Loại ghế không hợp lệ.'; end if;
    if x->>'kind'='couple' and (x->>'col_no')::integer>=30 then raise exception 'Ghế đôi cần hai vị trí liền kề.'; end if;
    insert into ghe(phong_chieu_id,loai_ghe_id,hang_ghe,so_ghe)
    select v_id,l.loai_ghe_id,chr(64+(x->>'row_no')::integer),(x->>'col_no')::integer from loai_ghe l
    where l.ten_loai_ghe=case x->>'kind' when 'vip' then 'VIP' when 'couple' then 'Đôi' else 'Thường' end;
   end loop;
   if exists(select 1 from ghe a join loai_ghe l on l.loai_ghe_id=a.loai_ghe_id join ghe b on a.phong_chieu_id=b.phong_chieu_id and a.hang_ghe=b.hang_ghe and a.so_ghe+1=b.so_ghe where a.phong_chieu_id=v_id and l.ten_loai_ghe='Đôi') then raise exception 'Ghế đôi chiếm hai vị trí, không được chồng lên ghế khác.'; end if;
  end if;
 elsif p_entity='showtimes' then
  if v_id is not null then perform cinema_expire(v_id); end if;
  select * into old_show from suat_chieu where suat_chieu_id=v_id;
  busy:=exists(select 1 from cinema_private.don_snapshot where suat_chieu_id=v_id) or exists(select 1 from ghe_suat_chieu where suat_chieu_id=v_id and trang_thai='GIU');
  if busy then
   if old_show.phim_id::text<>p_data->>'movie_id' or old_show.phong_chieu_id::text<>p_data->>'room_id' or old_show.thoi_gian_bat_dau<>(p_data->>'starts_at')::timestamptz or concat_ws(' ',old_show.dinh_dang_chieu,old_show.ngon_ngu_hien_thi)<>p_data->>'format' then raise exception 'Suất đã có giao dịch; chỉ được sửa giá cơ bản.'; end if;
   update suat_chieu set gia_ve_co_ban=(p_data->>'base_price')::numeric where suat_chieu_id=v_id; return v_id::text;
  end if;
  select * into movie_row from phim where phim_id=(p_data->>'movie_id')::bigint and trang_thai<>'NGUNG_CHIEU';
  room_id:=(p_data->>'room_id')::integer;
  if movie_row.phim_id is null or not exists(select 1 from phong_chieu where phong_chieu_id=room_id and trang_thai=1) or not exists(select 1 from ghe where phong_chieu_id=room_id and trang_thai=1) then raise exception 'Phim/phòng không khả dụng hoặc phòng chưa có sơ đồ.'; end if;
  start_time:=(p_data->>'starts_at')::timestamptz; end_time:=start_time+make_interval(mins=>movie_row.thoi_luong+15);
  if start_time<=now() then raise exception 'Giờ chiếu phải ở tương lai.'; end if;
  v_id:=coalesce(v_id,nextval(pg_get_serial_sequence('public.suat_chieu','suat_chieu_id')));
  perform pg_advisory_xact_lock(hashtextextended('show:'||v_id,0));
  insert into suat_chieu(suat_chieu_id,phim_id,phong_chieu_id,nhan_vien_id,thoi_gian_bat_dau,thoi_gian_ket_thuc,gia_ve_co_ban,dinh_dang_chieu,ngon_ngu_hien_thi,trang_thai)
  values(v_id,movie_row.phim_id,room_id,cinema_staff_id(),start_time,end_time,(p_data->>'base_price')::numeric,split_part(trim(p_data->>'format'),' ',1),nullif(trim(substr(trim(p_data->>'format'),length(split_part(trim(p_data->>'format'),' ',1))+1)),''),'DANG_MO_BAN')
  on conflict(suat_chieu_id) do update set phim_id=excluded.phim_id,phong_chieu_id=excluded.phong_chieu_id,nhan_vien_id=excluded.nhan_vien_id,thoi_gian_bat_dau=excluded.thoi_gian_bat_dau,thoi_gian_ket_thuc=excluded.thoi_gian_ket_thuc,gia_ve_co_ban=excluded.gia_ve_co_ban,dinh_dang_chieu=excluded.dinh_dang_chieu,ngon_ngu_hien_thi=excluded.ngon_ngu_hien_thi;
  delete from ghe_suat_chieu where suat_chieu_id=v_id;
  insert into ghe_suat_chieu(suat_chieu_id,ghe_id,trang_thai,gia_ban) select v_id,g.ghe_id,'TRONG',floor((p_data->>'base_price')::numeric*l.he_so_gia) from ghe g join loai_ghe l using(loai_ghe_id) where g.phong_chieu_id=room_id and g.trang_thai=1;
 elsif p_entity='promotions' then
  select * into old_promo from khuyen_mai where khuyen_mai_id=v_id for update;
  select count(distinct d.don_dat_ve_id) into used from don_dat_ve d join thanh_toan t using(don_dat_ve_id) where d.khuyen_mai_id=v_id and t.loai_giao_dich='THU' and t.trang_thai='THANH_CONG';
  if (p_data->>'max_uses')::integer<used then raise exception 'Số lượt tối đa không được nhỏ hơn số đã dùng.'; end if;
  v_id:=coalesce(v_id,nextval(pg_get_serial_sequence('public.khuyen_mai','khuyen_mai_id')));
  insert into khuyen_mai(khuyen_mai_id,nhan_vien_id,ma_khuyen_mai,ten_khuyen_mai,hinh_thuc_giam,gia_tri_giam,giam_toi_da,dieu_kien_ap_dung,ngay_bat_dau,ngay_ket_thuc,so_luong_toi_da,trang_thai)
  values(v_id,cinema_staff_id(),upper(trim(p_data->>'code')),p_data->>'name',case p_data->>'kind' when 'percent' then 'PHAN_TRAM' when 'fixed' then 'SO_TIEN' else p_data->>'kind' end,
   (p_data->>'value')::numeric,(p_data->>'max_discount')::numeric,(p_data->>'min_order')::numeric,(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,(p_data->>'max_uses')::integer,
   case p_data->>'status' when 'active' then 1 when 'paused' then 2 when 'stopped' then 0 else null end)
  on conflict(khuyen_mai_id) do update set nhan_vien_id=excluded.nhan_vien_id,ma_khuyen_mai=excluded.ma_khuyen_mai,ten_khuyen_mai=excluded.ten_khuyen_mai,hinh_thuc_giam=excluded.hinh_thuc_giam,gia_tri_giam=excluded.gia_tri_giam,
   giam_toi_da=excluded.giam_toi_da,dieu_kien_ap_dung=excluded.dieu_kien_ap_dung,ngay_bat_dau=excluded.ngay_bat_dau,ngay_ket_thuc=excluded.ngay_ket_thuc,so_luong_toi_da=excluded.so_luong_toi_da,trang_thai=excluded.trang_thai;
 else raise exception 'Danh mục không hợp lệ.';
 end if;
 return v_id::text;
end $$;

create or replace function public.cinema_vnpay_begin(p_order bigint,p_customer bigint,p_expected numeric) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare o don_dat_ve; p khuyen_mai; a cinema_private.vnpay_attempt; show_id bigint; n integer; discount numeric; why text;
begin
 select x.suat_chieu_id into show_id from cinema_private.don_snapshot x join don_dat_ve d using(don_dat_ve_id)
 where d.don_dat_ve_id=p_order and d.khach_hang_id=p_customer and exists(select 1 from khach_hang k where k.khach_hang_id=p_customer and k.trang_thai=1);
 if show_id is null then raise exception 'Không tìm thấy đơn.'; end if;
 perform cinema_expire(show_id);
 select * into o from don_dat_ve where don_dat_ve_id=p_order for update;
 if o.trang_thai='DA_THANH_TOAN' then return jsonb_build_object('paid',true); end if;
 if o.trang_thai<>'CHO_THANH_TOAN' or o.ngay_dat+interval '10 minutes'<=now() then raise exception 'Đơn đã hết hạn hoặc không thể thanh toán.'; end if;
 if exists(select 1 from cinema_private.vnpay_attempt where don_dat_ve_id=p_order and state='review') then raise exception 'Đơn cần đối soát VNPay. Vui lòng liên hệ nhân viên, không thanh toán lại.'; end if;
 select * into a from cinema_private.vnpay_attempt where don_dat_ve_id=p_order and state='pending' order by created_at desc limit 1;
 if a.ref is not null then return to_jsonb(a); end if;
 select jsonb_array_length(du_lieu->'order_items') into n from cinema_private.don_snapshot where don_dat_ve_id=p_order;
 if n=0 or (select count(*) from ghe_suat_chieu where don_dat_ve_id=p_order and trang_thai='GIU' and thoi_gian_giu_den>now())<>n then raise exception 'Ghế không còn được giữ cho đơn.'; end if;
 if o.khuyen_mai_id is not null then
  select * into p from khuyen_mai where khuyen_mai_id=o.khuyen_mai_id for update;
  begin discount:=cinema_promo_discount(p,o.tong_tien_goc); exception when others then why:=sqlerrm; discount:=0; end;
  if why is not null or discount<>o.giam_gia then
   if why is not null then update cinema_private.don_snapshot set du_lieu=du_lieu||jsonb_build_object('promotion_code',null) where don_dat_ve_id=p_order; end if;
   update don_dat_ve set khuyen_mai_id=case when why is null then p.khuyen_mai_id else null end,giam_gia=discount,tong_thanh_toan=tong_tien_goc-discount where don_dat_ve_id=p_order;
   return jsonb_build_object('price_changed',true,'total',o.tong_tien_goc-discount,'reason',coalesce(why,'Giá trị khuyến mãi đã thay đổi.'));
  end if;
 end if;
 if p_expected is distinct from o.tong_thanh_toan then return jsonb_build_object('price_changed',true,'total',o.tong_thanh_toan,'reason','Vui lòng xác nhận tổng tiền hiện tại.'); end if;
 if o.tong_thanh_toan<=0 then raise exception 'Đơn 0 đồng: vui lòng chọn thanh toán mô phỏng.'; end if;
 if not exists(select 1 from phuong_thuc_thanh_toan where ten_phuong_thuc='VNPay Sandbox' and trang_thai=1) then raise exception 'VNPay Sandbox chưa sẵn sàng.'; end if;
 insert into cinema_private.vnpay_attempt(ref,don_dat_ve_id,amount,expires_at)
 values('XYZ'||replace(gen_random_uuid()::text,'-',''),p_order,o.tong_thanh_toan,o.ngay_dat+interval '10 minutes') returning * into a;
 return to_jsonb(a);
end $$;

-- Chữ ký/merchant đã được xác minh tại route IPN trước RPC service-only này.
create or replace function public.cinema_vnpay_ipn(p_ref text,p_amount numeric,p_response text,p_status text,p_transaction text,p_pay_date text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare a cinema_private.vnpay_attempt; o don_dat_ve; show_id bigint; n integer; method_id integer; success boolean; paid_at timestamptz; can_deliver boolean; items jsonb;
begin
 select x.suat_chieu_id into show_id from cinema_private.vnpay_attempt v join cinema_private.don_snapshot x using(don_dat_ve_id) where v.ref=p_ref;
 if show_id is null then return jsonb_build_object('RspCode','01','Message','Order not found'); end if;
 -- Cùng thứ tự khóa với mô phỏng, hết hạn và hủy suất.
 perform cinema_expire(show_id);
 select d.* into o from don_dat_ve d join cinema_private.vnpay_attempt v using(don_dat_ve_id) where v.ref=p_ref for update of d;
 select * into a from cinema_private.vnpay_attempt where ref=p_ref for update;
 if p_amount is distinct from a.amount*100 then return jsonb_build_object('RspCode','04','Message','Invalid amount'); end if;
 success:=p_response='00' and p_status='00';
 if success and (p_transaction !~ '^[0-9]{1,30}$' or p_transaction='0' or p_pay_date !~ '^[0-9]{14}$') then return jsonb_build_object('RspCode','99','Message','Invalid transaction'); end if;
 if success then
  paid_at:=(substr(p_pay_date,1,4)||'-'||substr(p_pay_date,5,2)||'-'||substr(p_pay_date,7,2)||'T'||substr(p_pay_date,9,2)||':'||substr(p_pay_date,11,2)||':'||substr(p_pay_date,13,2)||'+07:00')::timestamptz;
  if paid_at<a.created_at-interval '5 seconds' or paid_at>now()+interval '5 minutes' then return jsonb_build_object('RspCode','99','Message','Invalid payment date'); end if;
 end if;
 if success and exists(select 1 from cinema_private.vnpay_attempt where provider_transaction=p_transaction and ref<>p_ref) then return jsonb_build_object('RspCode','99','Message','Transaction already used'); end if;
 if a.state='review' and not success then return jsonb_build_object('RspCode','02','Message','Order already confirmed'); end if;
 if a.state not in ('pending','review') then
  if success and a.state='failed' then
   update cinema_private.vnpay_attempt set state='review',response_code=p_response,transaction_status=p_status,provider_transaction=p_transaction,pay_date=p_pay_date,completed_at=now() where ref=p_ref;
  end if;
  return jsonb_build_object('RspCode','02','Message','Order already confirmed');
 end if;
 select phuong_thuc_id into method_id from phuong_thuc_thanh_toan where ten_phuong_thuc='VNPay Sandbox';
 if method_id is null then raise exception 'Thiếu danh mục VNPay Sandbox.'; end if;
 update cinema_private.vnpay_attempt set response_code=p_response,transaction_status=p_status,
  provider_transaction=case when success then p_transaction else null end,pay_date=p_pay_date,completed_at=now() where ref=p_ref;
 if not success then
  update cinema_private.vnpay_attempt set state='failed' where ref=p_ref;
  insert into thanh_toan(don_dat_ve_id,phuong_thuc_id,ma_giao_dich,so_tien,trang_thai,loai_giao_dich,noi_dung)
  values(o.don_dat_ve_id,method_id,p_ref,a.amount,'THAT_BAI','THU','VNPay Sandbox: response='||p_response||', status='||p_status);
  return jsonb_build_object('RspCode','00','Message','Confirm Success');
 end if;
 select du_lieu->'order_items' into items from cinema_private.don_snapshot where don_dat_ve_id=o.don_dat_ve_id;
 n:=jsonb_array_length(items);
 -- Có thể khôi phục đơn hết hạn khi khách đã trả đúng hạn và chính các ghế cũ vẫn trống.
 -- Không lấy ghế thuộc đơn khác, không đổi suất đã hủy/bắt đầu hoặc phục hồi đơn đã hủy.
 can_deliver:=o.trang_thai in ('CHO_THANH_TOAN','HET_HAN') and paid_at<=a.expires_at and o.tong_thanh_toan=a.amount and n>0
  and exists(select 1 from suat_chieu where suat_chieu_id=show_id and trang_thai<>'DA_HUY' and thoi_gian_bat_dau>now())
  and (select count(*) from ghe_suat_chieu g join jsonb_array_elements(items) i on g.ghe_suat_chieu_id=(i->>'id')::bigint
   where g.suat_chieu_id=show_id and g.ghe_id=(i->>'seat_id')::bigint
   and ((g.trang_thai='GIU' and g.don_dat_ve_id=o.don_dat_ve_id) or (g.trang_thai='TRONG' and g.don_dat_ve_id is null)))=n;
 if not coalesce(can_deliver,false) then
  -- Cổng báo thu thành công nhưng không thể giao ghế: giữ bằng chứng, không phát vé/chiếm ghế đã nhả.
  update cinema_private.vnpay_attempt set state='review' where ref=p_ref;
  return jsonb_build_object('RspCode','00','Message','Recorded for reconciliation');
 end if;
 insert into thanh_toan(don_dat_ve_id,phuong_thuc_id,ma_giao_dich,so_tien,trang_thai,loai_giao_dich,noi_dung,thoi_gian_thanh_toan)
 values(o.don_dat_ve_id,method_id,p_ref,a.amount,'THANH_CONG','THU','VNPay Sandbox · GD '||p_transaction,paid_at);
 update don_dat_ve set trang_thai='DA_THANH_TOAN' where don_dat_ve_id=o.don_dat_ve_id;
 update cinema_private.don_snapshot set ngay_thanh_toan=paid_at where don_dat_ve_id=o.don_dat_ve_id;
 update ghe_suat_chieu g set trang_thai='DA_BAN',don_dat_ve_id=o.don_dat_ve_id,gia_ban=(i->>'price')::numeric,
  khach_giu_id=null,ma_luot_giu=null,thoi_gian_giu_den=null
 from jsonb_array_elements(items) i where g.ghe_suat_chieu_id=(i->>'id')::bigint and g.suat_chieu_id=show_id;
 insert into ve(don_dat_ve_id,ghe_suat_chieu_id,gia_ve,trang_thai) select o.don_dat_ve_id,ghe_suat_chieu_id,gia_ban,'HIEU_LUC' from ghe_suat_chieu where don_dat_ve_id=o.don_dat_ve_id;
 update cinema_private.vnpay_attempt set state='paid' where ref=p_ref;
 return jsonb_build_object('RspCode','00','Message','Confirm Success');
end $$;

create or replace function public.cinema_vnpay_lookup(p_ref text) returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('order_id',a.don_dat_ve_id::text,'state',a.state,'amount',a.amount,'created_at',a.created_at,'expires_at',a.expires_at,'customer_id',d.khach_hang_id::text)
 from cinema_private.vnpay_attempt a join don_dat_ve d using(don_dat_ve_id) where a.ref=p_ref
$$;
create or replace function public.cinema_vnpay_query_attempt(p_order bigint,p_customer bigint) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare a cinema_private.vnpay_attempt;
begin
 if not exists(select 1 from don_dat_ve where don_dat_ve_id=p_order and khach_hang_id=p_customer) then raise exception 'Không tìm thấy đơn.'; end if;
 select * into a from cinema_private.vnpay_attempt where don_dat_ve_id=p_order order by created_at desc limit 1 for update;
 if a.ref is null or a.state in ('paid','failed') then return null; end if;
 if a.last_query_at>now()-interval '60 seconds' then return jsonb_build_object('throttled',true,'state',a.state); end if;
 update cinema_private.vnpay_attempt set last_query_at=now() where ref=a.ref;
 return to_jsonb(a);
end $$;
revoke all on function cinema_vnpay_query_attempt(bigint,bigint) from public,anon,authenticated;
grant execute on function cinema_vnpay_query_attempt(bigint,bigint) to service_role;
revoke all on function cinema_vnpay_begin(bigint,bigint,numeric),cinema_vnpay_ipn(text,numeric,text,text,text,text),cinema_vnpay_lookup(text) from public,anon,authenticated;
grant usage on schema public to service_role;
grant execute on function cinema_vnpay_begin(bigint,bigint,numeric),cinema_vnpay_ipn(text,numeric,text,text,text,text),cinema_vnpay_lookup(text) to service_role;


insert into phuong_thuc_thanh_toan(ten_phuong_thuc,mo_ta,trang_thai)
select 'VNPay Sandbox','Cổng thanh toán thử nghiệm VNPay 2.1.0',1 where not exists(select 1 from phuong_thuc_thanh_toan where ten_phuong_thuc='VNPay Sandbox');
update phuong_thuc_thanh_toan set trang_thai=1,mo_ta='Cổng thanh toán thử nghiệm VNPay 2.1.0' where ten_phuong_thuc='VNPay Sandbox';

-- Cập nhật các chính sách đã biết trong một giao dịch; không xóa bảng.
do $$ declare p record; begin
 for p in select schemaname,tablename,policyname from pg_policies where schemaname='public' and tablename=any(array['khach_hang','nhan_vien','the_loai','phim','phim_the_loai','phong_chieu','loai_ghe','ghe','suat_chieu','ghe_suat_chieu','don_dat_ve','ve','khuyen_mai','phuong_thuc_thanh_toan','thanh_toan']) and policyname=any(array['staff_read','staff_read','public_genres','public_movies','public_movie_genres','public_rooms','public_seat_types','public_seats','public_shows','own_customer','own_employee','own_orders','own_show_seats','own_tickets','own_transactions']) loop
  execute format('drop policy %I on %I.%I',p.policyname,p.schemaname,p.tablename);
 end loop;
end $$;
-- RLS trên đủ 15 bảng. Không cấp quyền ghi trực tiếp cho trình duyệt.
do $$ declare t text; begin
 foreach t in array array['khach_hang','nhan_vien','the_loai','phim','phim_the_loai','phong_chieu','loai_ghe','ghe','suat_chieu','ghe_suat_chieu','don_dat_ve','ve','khuyen_mai','phuong_thuc_thanh_toan','thanh_toan'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  if t not in ('khach_hang','nhan_vien') then execute format('grant select on public.%I to anon,authenticated',t); end if;
  execute format('create policy staff_read on public.%I for select to anon,authenticated using (public.cinema_staff())',t);
 end loop;
end $$;
grant select(khach_hang_id,ho_ten,email,so_dien_thoai,ngay_sinh,gioi_tinh,trang_thai,ngay_tao) on khach_hang to anon,authenticated;
grant select(nhan_vien_id,ho_ten,email,so_dien_thoai,vai_tro,ten_dang_nhap,trang_thai,ngay_tao) on nhan_vien to anon,authenticated;
grant select on the_loai,phim,phim_the_loai,phong_chieu,loai_ghe,ghe,suat_chieu to anon;
create policy public_genres on the_loai for select using(true);
create policy public_movies on phim for select using(trang_thai<>'NGUNG_CHIEU');
create policy public_movie_genres on phim_the_loai for select using(exists(select 1 from phim p where p.phim_id=phim_the_loai.phim_id and p.trang_thai<>'NGUNG_CHIEU'));
create policy public_rooms on phong_chieu for select using(true);
create policy public_seat_types on loai_ghe for select using(true);
create policy public_seats on ghe for select using(true);
create policy public_shows on suat_chieu for select using(trang_thai<>'DA_HUY' and exists(select 1 from phim p where p.phim_id=suat_chieu.phim_id and p.trang_thai<>'NGUNG_CHIEU'));
create policy own_customer on khach_hang for select using(khach_hang_id=cinema_customer_id());
create policy own_employee on nhan_vien for select using(nhan_vien_id=cinema_staff_id());
create policy own_orders on don_dat_ve for select using(khach_hang_id=cinema_customer_id());
create policy own_show_seats on ghe_suat_chieu for select using(khach_giu_id=cinema_customer_id() or exists(select 1 from don_dat_ve d where d.don_dat_ve_id=ghe_suat_chieu.don_dat_ve_id and d.khach_hang_id=cinema_customer_id()));
create policy own_tickets on ve for select using(exists(select 1 from don_dat_ve d where d.don_dat_ve_id=ve.don_dat_ve_id and d.khach_hang_id=cinema_customer_id()));
create policy own_transactions on thanh_toan for select using(exists(select 1 from don_dat_ve d where d.don_dat_ve_id=thanh_toan.don_dat_ve_id and d.khach_hang_id=cinema_customer_id()));
-- Mọi helper/trigger mặc định đóng; chỉ mở các RPC đã kiểm tra quyền.
do $$ declare f record; begin
 for f in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname=any(array['cinema_check_show','cinema_check_show_seat','cinema_check_transaction','cinema_check_ticket','cinema_session_hash','cinema_customer_id','cinema_staff_id','cinema_staff','cinema_customer','cinema_profile','cinema_new_session','cinema_register','cinema_login','cinema_logout','cinema_change_password','cinema_grant_staff','cinema_expire','cinema_pay','cinema_cancel_internal','cinema_cancel','cinema_stop_show','cinema_expire_all','cinema_seat_json','cinema_seatmap','cinema_hold','cinema_release','cinema_order','cinema_promo_discount','cinema_promo','cinema_catalog','cinema_order_json','cinema_orders','cinema_hold_details','cinema_reservation','cinema_admin','cinema_version','cinema_admin_save']) loop
  execute format('revoke all on function %s from public,anon,authenticated',f.sig);
 end loop;
end $$;
revoke all on all tables in schema cinema_private from public,anon,authenticated;
do $$ declare s record; begin
 for s in select pg_get_serial_sequence('public.'||c.table_name,c.column_name) seq from information_schema.columns c
 where c.table_schema='public' and c.is_identity='YES' and c.table_name in ('khach_hang','nhan_vien','the_loai','phim','phong_chieu','loai_ghe','ghe','suat_chieu','ghe_suat_chieu','don_dat_ve','ve','khuyen_mai','phuong_thuc_thanh_toan','thanh_toan')
 loop execute format('revoke all on sequence %s from anon,authenticated',s.seq); end loop;
end $$;
grant execute on function cinema_staff(),cinema_customer_id(),cinema_staff_id() to anon,authenticated;
grant execute on function cinema_catalog(),cinema_seatmap(bigint) to anon,authenticated;
grant execute on function cinema_version() to anon,authenticated;
grant execute on function cinema_profile(),cinema_orders(bigint),cinema_hold_details(text),cinema_reservation(bigint),cinema_admin(),
 cinema_hold(bigint,bigint[]),cinema_release(text),cinema_order(text,numeric),cinema_promo(bigint,text),cinema_pay(bigint,numeric),cinema_cancel(bigint),cinema_stop_show(bigint,jsonb),cinema_admin_save(text,jsonb),
 cinema_register(text,text,text,text),cinema_login(text,text,boolean),cinema_logout(),cinema_change_password(text,text) to anon,authenticated;

-- Lưu mã khuyến mãi tại thời điểm nâng cấp cho các đơn cũ chưa có snapshot mã.
update cinema_private.don_snapshot x set du_lieu=x.du_lieu||jsonb_build_object('promotion_code',p.ma_khuyen_mai)
from don_dat_ve d left join khuyen_mai p using(khuyen_mai_id)
where x.don_dat_ve_id=d.don_dat_ve_id and not (x.du_lieu ? 'promotion_code');
create index if not exists cinema_inventory_expiry on public.ghe_suat_chieu(suat_chieu_id,thoi_gian_giu_den) where trang_thai='GIU';
create index if not exists cinema_snapshot_show on cinema_private.don_snapshot(suat_chieu_id);
create index if not exists cinema_transactions_order on public.thanh_toan(don_dat_ve_id,loai_giao_dich,trang_thai);
create index if not exists cinema_tickets_order on public.ve(don_dat_ve_id);
create index if not exists cinema_session_expiry on cinema_private.phien_dang_nhap(het_han);
update cinema_private.cau_hinh set schema_version='chapter3-audit-v2' where id;
notify pgrst,'reload schema';
commit;
select public.cinema_version() as phien_ban;

