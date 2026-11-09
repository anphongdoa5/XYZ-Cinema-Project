create function public.cinema_admin_save(p_entity text,p_data jsonb) returns text language plpgsql security definer set search_path=public,pg_temp as $$
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
