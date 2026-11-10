-- BR02/BR13: quét theo giờ máy chủ, chỉ nhả ghế còn thuộc đúng đơn quá hạn.
create function public.cinema_expire(p_show bigint) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('show:'||p_show,0));
 update don_dat_ve d set trang_thai='HET_HAN' from cinema_private.don_snapshot x
 where x.don_dat_ve_id=d.don_dat_ve_id and x.suat_chieu_id=p_show and d.trang_thai in ('MOI_TAO','CHO_THANH_TOAN') and d.ngay_dat+interval '10 minutes'<=now();
 update ghe_suat_chieu g set trang_thai='TRONG',don_dat_ve_id=null,khach_giu_id=null,ma_luot_giu=null,thoi_gian_giu_den=null
 where g.suat_chieu_id=p_show and g.trang_thai='GIU' and g.thoi_gian_giu_den<=now()
 and (g.don_dat_ve_id is null or exists(select 1 from don_dat_ve d where d.don_dat_ve_id=g.don_dat_ve_id and d.trang_thai='HET_HAN'));
end $$;
-- Thanh toán mô phỏng được giữ để báo cáo; khóa khi VNPay đang xử lý.
create function public.cinema_pay(p_order bigint,p_expected numeric) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
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

create function public.cinema_cancel_internal(p_order bigint) returns void language plpgsql security definer set search_path=public,pg_temp as $$
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
create function public.cinema_cancel(p_order bigint) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
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
create function public.cinema_stop_show(p_show bigint,p_expected jsonb) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
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
create function public.cinema_expire_all() returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare s record;
begin
 for s in select distinct suat_chieu_id from ghe_suat_chieu where trang_thai='GIU' and thoi_gian_giu_den<=now() order by suat_chieu_id loop perform cinema_expire(s.suat_chieu_id); end loop;
 delete from cinema_private.phien_dang_nhap where het_han<=now();
 delete from cinema_private.gioi_han_dang_nhap where bat_dau<now()-interval '1 day';
end $$;
create function public.cinema_seat_json(p_seat bigint) returns jsonb language sql stable set search_path=public,pg_temp as $$
 select jsonb_build_object('id',g.ghe_id::text,'room_id',g.phong_chieu_id::text,
 'label',g.hang_ghe||case when l.ten_loai_ghe='Đôi' then g.so_ghe||'-'||(g.so_ghe+1) else g.so_ghe::text end,
 'row_no',ascii(g.hang_ghe)-64,'col_no',g.so_ghe,'kind',case l.ten_loai_ghe when 'VIP' then 'vip' when 'Đôi' then 'couple' else 'standard' end)
 from ghe g join loai_ghe l using(loai_ghe_id) where g.ghe_id=p_seat
$$;
create function public.cinema_seatmap(p_show bigint) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
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
create function public.cinema_hold(p_show bigint,p_seats bigint[]) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
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
create function public.cinema_release(p_hold text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare show_id bigint;
begin
 perform cinema_customer(); select suat_chieu_id into show_id from ghe_suat_chieu where ma_luot_giu=p_hold and khach_giu_id=cinema_customer_id() limit 1;
 if show_id is null then raise exception 'Không tìm thấy phiên giữ ghế.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('show:'||show_id,0));
 update ghe_suat_chieu set trang_thai='TRONG',khach_giu_id=null,ma_luot_giu=null,thoi_gian_giu_den=null where ma_luot_giu=p_hold and khach_giu_id=cinema_customer_id() and don_dat_ve_id is null;
end $$;
create function public.cinema_order(p_hold text,p_expected numeric) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
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
create function public.cinema_promo_discount(p khuyen_mai,p_subtotal numeric) returns numeric language plpgsql set search_path=public,pg_temp as $$
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
create function public.cinema_promo(p_order bigint,p_code text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
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
