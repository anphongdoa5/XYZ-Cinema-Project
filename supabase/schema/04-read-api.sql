-- Chuyển tên trường sang hợp đồng JSON của giao diện; dữ liệu gốc vẫn là 15 bảng Chương 3.
create function public.cinema_catalog() returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
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
create function public.cinema_order_json(p_order bigint) returns jsonb language sql stable set search_path=public,pg_temp as $$
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
create function public.cinema_orders(p_order bigint default null) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
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
create function public.cinema_hold_details(p_hold text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
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
create function public.cinema_reservation(p_show bigint) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform cinema_customer(); perform cinema_expire(p_show);
 return jsonb_build_object('holdId',(select ma_luot_giu from ghe_suat_chieu where suat_chieu_id=p_show and khach_giu_id=cinema_customer_id() and trang_thai='GIU' order by thoi_gian_giu_den desc limit 1),
 'orderId',(select d.don_dat_ve_id::text from don_dat_ve d join cinema_private.don_snapshot x using(don_dat_ve_id) where x.suat_chieu_id=p_show and d.khach_hang_id=cinema_customer_id() and d.trang_thai='CHO_THANH_TOAN' and d.ngay_dat+interval '10 minutes'>now() order by d.ngay_dat desc limit 1),'server_now',now());
end $$;
create function public.cinema_admin() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
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

-- Dùng cho chẩn đoán phiên bản, không trả dữ liệu tài khoản hay token.
create function public.cinema_version() returns text language sql stable security definer set search_path=public,pg_temp as $$ select schema_version from cinema_private.cau_hinh where id $$;
