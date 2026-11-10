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

-- BEGIN RPC
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
-- BEGIN ACTIVATION
insert into phuong_thuc_thanh_toan(ten_phuong_thuc,mo_ta,trang_thai)
select 'VNPay Sandbox','Cổng thanh toán thử nghiệm VNPay 2.1.0',1 where not exists(select 1 from phuong_thuc_thanh_toan where ten_phuong_thuc='VNPay Sandbox');
update phuong_thuc_thanh_toan set trang_thai=1,mo_ta='Cổng thanh toán thử nghiệm VNPay 2.1.0' where ten_phuong_thuc='VNPay Sandbox';
