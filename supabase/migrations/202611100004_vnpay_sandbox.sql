-- XYZ Cinema · Chương 3, Bảng 3.1–3.17.
-- Sinh bằng node scripts/build-database.mjs; nguồn trong supabase/schema/.
-- Nâng cấp VNPay Sandbox giữ dữ liệu. Không chạy reset/install trước tệp này.
begin;
set local search_path=public,extensions,pg_temp;
select pg_advisory_xact_lock(hashtextextended('xyz_cinema_install',0));
-- Chỉ máy chủ giữ service key được gọi các RPC VNPay. Không thêm bảng nghiệp vụ public.
create table if not exists cinema_private.vnpay_attempt (
 ref varchar(40) primary key,
 don_dat_ve_id bigint not null references public.don_dat_ve(don_dat_ve_id),
 amount numeric(10,0) not null check(amount>0),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null,
 state text not null default 'pending' check(state in ('pending','paid','failed','review')),
 response_code text, transaction_status text, provider_transaction text unique,
 pay_date text, completed_at timestamptz
);
create index if not exists cinema_vnpay_order on cinema_private.vnpay_attempt(don_dat_ve_id,created_at desc);
revoke all on cinema_private.vnpay_attempt from public,anon,authenticated;


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
declare a cinema_private.vnpay_attempt; o don_dat_ve; show_id bigint; n integer; method_id integer; success boolean;
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
 if success and exists(select 1 from cinema_private.vnpay_attempt where provider_transaction=p_transaction and ref<>p_ref) then return jsonb_build_object('RspCode','99','Message','Transaction already used'); end if;
 if a.state<>'pending' then
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
 select jsonb_array_length(du_lieu->'order_items') into n from cinema_private.don_snapshot where don_dat_ve_id=o.don_dat_ve_id;
 if o.trang_thai<>'CHO_THANH_TOAN' or a.expires_at<=now() or o.tong_thanh_toan<>a.amount or n=0
  or (select count(*) from ghe_suat_chieu where don_dat_ve_id=o.don_dat_ve_id and trang_thai='GIU' and thoi_gian_giu_den>now())<>n
  or not exists(select 1 from suat_chieu where suat_chieu_id=show_id and trang_thai<>'DA_HUY') then
  -- Cổng báo thu thành công nhưng không thể giao ghế: giữ bằng chứng, không phát vé/chiếm ghế đã nhả.
  update cinema_private.vnpay_attempt set state='review' where ref=p_ref;
  return jsonb_build_object('RspCode','00','Message','Recorded for reconciliation');
 end if;
 insert into thanh_toan(don_dat_ve_id,phuong_thuc_id,ma_giao_dich,so_tien,trang_thai,loai_giao_dich,noi_dung)
 values(o.don_dat_ve_id,method_id,p_ref,a.amount,'THANH_CONG','THU','VNPay Sandbox · GD '||p_transaction);
 update don_dat_ve set trang_thai='DA_THANH_TOAN' where don_dat_ve_id=o.don_dat_ve_id;
 update cinema_private.don_snapshot set ngay_thanh_toan=now() where don_dat_ve_id=o.don_dat_ve_id;
 update ghe_suat_chieu set trang_thai='DA_BAN',thoi_gian_giu_den=null where don_dat_ve_id=o.don_dat_ve_id;
 insert into ve(don_dat_ve_id,ghe_suat_chieu_id,gia_ve,trang_thai) select o.don_dat_ve_id,ghe_suat_chieu_id,gia_ban,'HIEU_LUC' from ghe_suat_chieu where don_dat_ve_id=o.don_dat_ve_id;
 update cinema_private.vnpay_attempt set state='paid' where ref=p_ref;
 return jsonb_build_object('RspCode','00','Message','Confirm Success');
end $$;

create or replace function public.cinema_vnpay_lookup(p_ref text) returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('order_id',don_dat_ve_id::text,'state',state) from cinema_private.vnpay_attempt where ref=p_ref
$$;
revoke all on function cinema_vnpay_begin(bigint,bigint,numeric),cinema_vnpay_ipn(text,numeric,text,text,text,text),cinema_vnpay_lookup(text) from public,anon,authenticated;
grant usage on schema public to service_role;
grant execute on function cinema_vnpay_begin(bigint,bigint,numeric),cinema_vnpay_ipn(text,numeric,text,text,text,text),cinema_vnpay_lookup(text) to service_role;


insert into phuong_thuc_thanh_toan(ten_phuong_thuc,mo_ta,trang_thai)
select 'VNPay Sandbox','Cổng thanh toán thử nghiệm VNPay 2.1.0',1 where not exists(select 1 from phuong_thuc_thanh_toan where ten_phuong_thuc='VNPay Sandbox');
update phuong_thuc_thanh_toan set trang_thai=1,mo_ta='Cổng thanh toán thử nghiệm VNPay 2.1.0' where ten_phuong_thuc='VNPay Sandbox';
notify pgrst,'reload schema';
commit;
select 'vnpay-sandbox-v1' as cap_nhat;
