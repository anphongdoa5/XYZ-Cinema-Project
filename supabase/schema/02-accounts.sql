-- Phiên ngẫu nhiên 256 bit; chỉ lưu SHA-256 trong schema kỹ thuật.
create function public.cinema_session_hash() returns text language sql stable set search_path=public,extensions,pg_temp as $$
 select encode(digest(coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-cinema-session',''),'sha256'),'hex')
$$;
create function public.cinema_customer_id() returns bigint language sql stable security definer set search_path=public,extensions,pg_temp as $$
 select k.khach_hang_id from cinema_private.phien_dang_nhap s join khach_hang k using(khach_hang_id) where s.token_hash=cinema_session_hash() and s.het_han>now() and k.trang_thai=1
$$;
create function public.cinema_staff_id() returns bigint language sql stable security definer set search_path=public,extensions,pg_temp as $$
 select n.nhan_vien_id from cinema_private.phien_dang_nhap s join nhan_vien n using(nhan_vien_id) where s.token_hash=cinema_session_hash() and s.het_han>now() and n.trang_thai=1
$$;
create function public.cinema_staff() returns boolean language sql stable security definer set search_path=public,extensions,pg_temp as $$ select cinema_staff_id() is not null $$;
create function public.cinema_customer() returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
begin
 if cinema_customer_id() is null then raise exception 'Vui lòng đăng nhập bằng tài khoản khách hàng đang hoạt động.'; end if;
end $$;
create function public.cinema_profile() returns jsonb language plpgsql stable security definer set search_path=public,extensions,pg_temp as $$
declare result jsonb;
begin
 select jsonb_build_object('id',k.khach_hang_id::text,'full_name',k.ho_ten,'email',k.email,'phone',k.so_dien_thoai,'active',k.trang_thai=1,'role','customer') into result from khach_hang k where k.khach_hang_id=cinema_customer_id();
 if result is null then
  select jsonb_build_object('id',n.nhan_vien_id::text,'full_name',n.ho_ten,'email',n.email,'phone',n.so_dien_thoai,'active',n.trang_thai=1,'role',case n.vai_tro when 'QUAN_TRI' then 'admin' else 'staff' end) into result from nhan_vien n where n.nhan_vien_id=cinema_staff_id();
 end if;
 return result;
end $$;
create function public.cinema_new_session(p_customer bigint,p_staff bigint) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare token text:=encode(gen_random_bytes(32),'hex'); expires timestamptz:=now()+interval '7 days';
begin
 delete from cinema_private.phien_dang_nhap where het_han<=now();
 insert into cinema_private.phien_dang_nhap(token_hash,khach_hang_id,nhan_vien_id,het_han) values(encode(digest(token,'sha256'),'hex'),p_customer,p_staff,expires);
 return jsonb_build_object('token',token,'expires_at',expires);
end $$;
create function public.cinema_register(p_name text,p_email text,p_phone text,p_password text) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare customer_id bigint;
begin
 if length(p_password)<8 or octet_length(p_password)>72 then raise exception 'Mật khẩu cần ít nhất 8 ký tự và tối đa 72 byte UTF-8.'; end if;
 if length(trim(p_name)) not between 1 and 100 or length(trim(p_email))>100 or trim(p_email) !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or trim(p_phone) !~ '^\+?[0-9]{9,15}$' then raise exception 'Họ tên, email hoặc số điện thoại chưa hợp lệ.'; end if;
 insert into khach_hang(ho_ten,email,so_dien_thoai,mat_khau) values(trim(p_name),lower(trim(p_email)),trim(p_phone),crypt(p_password,gen_salt('bf',12))) returning khach_hang_id into customer_id;
 return cinema_new_session(customer_id,null);
exception when unique_violation then raise exception 'Email hoặc số điện thoại đã được sử dụng.';
end $$;
create function public.cinema_login(p_login text,p_password text,p_staff boolean default false) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
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
create function public.cinema_logout() returns void language sql security definer set search_path=public,extensions,pg_temp as $$ delete from cinema_private.phien_dang_nhap where token_hash=cinema_session_hash() $$;
create function public.cinema_change_password(p_current text,p_new text) returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
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
-- Chỉ DB owner được cấp nhân viên; không mở hàm này cho API.
create function public.cinema_grant_staff(p_email text,p_role text default 'NHAN_VIEN',p_username text default null) returns bigint language plpgsql security definer set search_path=public,extensions,pg_temp as $$
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
