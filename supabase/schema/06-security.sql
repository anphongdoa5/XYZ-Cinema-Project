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
