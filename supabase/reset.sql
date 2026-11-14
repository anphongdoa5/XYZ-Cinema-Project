-- NGUY HIỂM: XÓA dữ liệu XYZ Cinema cũ/mới: đơn, vé, giao dịch, phim, ghế...
-- Chỉ dùng project phát triển; tải/xuất dữ liệu cần giữ trước khi Run.
-- KHÔNG xóa auth.users, schema auth/storage hoặc toàn bộ schema public.
-- RESTRICT: nếu đối tượng ngoài XYZ Cinema phụ thuộc, toàn bộ reset dừng/rollback.
begin;
do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  execute $job$select cron.unschedule(jobid) from cron.job where jobname='xyz-cinema-expire'$job$;
 end if;
end $$;
do $$
declare obj record;
 owned text[]:=array['profiles','movies','rooms','seats','showtimes','holds','promotions','orders','order_items','show_seats','transactions','tickets','cinema_settings',
 'nhat_ky_hoat_dong','khach_hang','nhan_vien','the_loai','phim','phim_the_loai','phong_chieu','loai_ghe','ghe','suat_chieu','ghe_suat_chieu','don_dat_ve','ve','khuyen_mai','phuong_thuc_thanh_toan','thanh_toan'];
 names text[]:=array['cinema_role','cinema_is_admin','cinema_audit','cinema_audit_change','cinema_guard_admin','cinema_employee_save','cinema_employees','cinema_logs','cinema_support_search','cinema_support_cancel','cinema_operations','cinema_check_in','cinema_staff','cinema_customer','cinema_new_user','cinema_expire','cinema_seatmap','cinema_hold','cinema_release','cinema_order','cinema_promo_discount','cinema_promo','cinema_pay','cinema_cancel_internal','cinema_cancel','cinema_stop_show','cinema_admin_save',
 'cinema_check_show','cinema_check_show_seat','cinema_check_transaction','cinema_check_ticket','cinema_customer_id','cinema_staff_id','cinema_sync_auth_user','cinema_profile','cinema_grant_staff','cinema_expire_all','cinema_seat_json','cinema_catalog','cinema_order_json','cinema_orders','cinema_hold_details','cinema_reservation','cinema_admin',
 'cinema_session_hash','cinema_new_session','cinema_register','cinema_login','cinema_logout','cinema_change_password','cinema_version','cinema_vnpay_begin','cinema_vnpay_ipn','cinema_vnpay_lookup','cinema_vnpay_query_attempt'];
begin
 for obj in select p.schemaname,p.tablename,p.policyname from pg_policies p where p.schemaname='public' and p.tablename=any(owned) loop
  execute format('drop policy %I on %I.%I',obj.policyname,obj.schemaname,obj.tablename);
 end loop;
 for obj in select n.nspname,c.relname,t.tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
 where not t.tgisinternal and ((n.nspname='public' and c.relname=any(owned)) or (n.nspname='auth' and c.relname='users' and t.tgname in ('cinema_user_created','cinema_auth_profile_sync'))) loop
  execute format('drop trigger %I on %I.%I',obj.tgname,obj.nspname,obj.relname);
 end loop;
 for obj in select p.oid::regprocedure signature from pg_proc p where p.pronamespace='public'::regnamespace and p.proname=any(names) loop
  execute format('drop function %s restrict',obj.signature);
 end loop;
end $$;
drop table if exists
 cinema_private.vnpay_attempt,cinema_private.auth_link,cinema_private.phien_dang_nhap,cinema_private.gioi_han_dang_nhap,cinema_private.phim_hien_thi,cinema_private.don_snapshot,cinema_private.cau_hinh,
 public.nhat_ky_hoat_dong,public.ve,public.thanh_toan,public.ghe_suat_chieu,public.don_dat_ve,public.khuyen_mai,
 public.phuong_thuc_thanh_toan,public.suat_chieu,public.ghe,public.loai_ghe,public.phong_chieu,
 public.phim_the_loai,public.the_loai,public.phim,public.khach_hang,public.nhan_vien,
 public.tickets,public.transactions,public.show_seats,public.order_items,public.orders,
 public.holds,public.promotions,public.showtimes,public.seats,public.rooms,public.movies,public.profiles,public.cinema_settings restrict;
drop schema if exists cinema_private restrict;
commit;
select 'Đã xóa cấu trúc XYZ Cinema. Tài khoản Supabase Auth vẫn được giữ. Tiếp theo chạy TOÀN BỘ supabase/deploy.sql bản mới.' as ket_qua;
