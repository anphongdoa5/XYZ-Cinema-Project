-- XYZ Cinema · Chương 3, Bảng 3.1–3.17.
-- Sinh bằng node scripts/build-database.mjs; nguồn trong supabase/schema/.
-- CẬP NHẬT TÂM ĐIỂM THEO VÉ BÁN TRONG TUẦN. Không reset/cài lại database.
-- Chỉ thay hàm đọc catalog; giữ nguyên bảng, cột, tài khoản, đơn, vé và giao dịch.
begin;
set local search_path=public,extensions,pg_temp;
do $$ begin
 perform pg_advisory_xact_lock(hashtextextended('xyz_cinema_install',0));
 if to_regprocedure('public.cinema_catalog()') is null or to_regclass('public.ve') is null then
  raise exception 'Cần cài database Chương 3 trước khi cập nhật Tâm điểm.';
 end if;
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
notify pgrst,'reload schema';
commit;
select 'weekly-feature-v1' as cap_nhat;

