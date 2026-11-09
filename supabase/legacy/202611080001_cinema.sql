-- XYZ Cinema · run once in Supabase SQL Editor. All business writes are atomic RPCs.
begin;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '', phone text unique, role text not null default 'customer' check(role in ('customer','staff')),
 active boolean not null default true, created_at timestamptz not null default now()
);
create function public.cinema_staff() returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from profiles where id=auth.uid() and role='staff' and active)
$$;
create function public.cinema_customer() returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from profiles where id=auth.uid() and role='customer' and active) then raise exception 'Vui lòng đăng nhập bằng tài khoản khách hàng đang hoạt động.'; end if;
end $$;
create function public.cinema_new_user() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 insert into profiles(id,full_name,phone) values(new.id,left(coalesce(new.raw_user_meta_data->>'full_name',''),100),nullif(new.raw_user_meta_data->>'phone',''));
 return new;
end $$;
create trigger cinema_user_created after insert on auth.users for each row execute function public.cinema_new_user();
insert into profiles(id,full_name,phone) select id,left(coalesce(raw_user_meta_data->>'full_name',''),100),nullif(raw_user_meta_data->>'phone','') from auth.users on conflict(id) do nothing;
create table public.movies (
 id uuid primary key default gen_random_uuid(), title text not null check(length(title) between 1 and 255), duration integer not null check(duration>0 and duration<=600),
 genres text not null, age text not null check(age in ('P','C13','C16','C18')), language text not null default 'Tiếng Việt',
 description text not null default '', poster_url text not null default '', trailer_url text not null default '', director text not null default '', actors text not null default '', country text not null default '',
 release_date date, status text not null default 'coming' check(status in ('showing','coming','stopped')), created_at timestamptz not null default now()
);
create table public.rooms (
 id uuid primary key default gen_random_uuid(), name text not null unique, format text not null default '2D', status text not null default 'active' check(status in ('active','maintenance'))
);
create table public.seats (
 id uuid primary key default gen_random_uuid(), room_id uuid not null references rooms(id), label text not null, row_no integer not null check(row_no between 1 and 20), col_no integer not null check(col_no between 1 and 30),
 kind text not null check(kind in ('standard','vip','couple')), unique(room_id,label), unique(room_id,row_no,col_no)
);
create table public.showtimes (
 id uuid primary key default gen_random_uuid(), movie_id uuid not null references movies(id), room_id uuid not null references rooms(id), starts_at timestamptz not null, ends_at timestamptz not null,
 format text not null default '2D phụ đề', base_price integer not null check(base_price>0 and base_price<=10000000), status text not null default 'open' check(status in ('open','closed','stopped'))
);
create index on showtimes(room_id,starts_at);
create table public.holds (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles(id), showtime_id uuid not null references showtimes(id),
 expires_at timestamptz not null, status text not null default 'active' check(status in ('active','released','converted','expired')), quoted_total integer not null
);
create table public.promotions (
 id uuid primary key default gen_random_uuid(), code text not null unique check(code=upper(trim(code)) and length(code) between 1 and 50), name text not null,
 kind text not null check(kind in ('percent','fixed')), value integer not null check(value>0), max_discount integer not null check(max_discount>=0), min_order integer not null default 0 check(min_order>=0),
 starts_at timestamptz not null, ends_at timestamptz not null, max_uses integer not null check(max_uses>0), used_count integer not null default 0 check(used_count>=0 and used_count<=max_uses),
 status text not null default 'active' check(status in ('active','paused','stopped')), check(ends_at>=starts_at), check(kind<>'percent' or value<=100)
);
create table public.orders (
 id uuid primary key default gen_random_uuid(), code text not null unique default ('XYZ'||to_char(now() at time zone 'Asia/Ho_Chi_Minh','YYMMDD')||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
 user_id uuid not null references profiles(id), showtime_id uuid not null references showtimes(id), hold_id uuid not null unique references holds(id),
 status text not null default 'pending' check(status in ('pending','paid','cancelled','expired')), subtotal integer not null, discount integer not null default 0,
 total integer not null, promotion_id uuid references promotions(id), promotion_code text, created_at timestamptz not null default now(), expires_at timestamptz not null, paid_at timestamptz, cancelled_at timestamptz,
 movie_title text not null, room_name text not null, show_starts_at timestamptz not null, show_format text not null,
 check(total=subtotal-discount and total>=0)
);
create index on orders(user_id,created_at desc);
create table public.order_items (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references orders(id), seat_id uuid not null references seats(id), label text not null, kind text not null, price integer not null, unique(order_id,seat_id)
);
create table public.show_seats (
 showtime_id uuid not null references showtimes(id) on delete cascade, seat_id uuid not null references seats(id), status text not null default 'available' check(status in ('available','held','sold')),
 hold_id uuid references holds(id), order_id uuid references orders(id), expires_at timestamptz, primary key(showtime_id,seat_id)
);
create table public.transactions (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references orders(id), kind text not null check(kind in ('payment','refund')),
 result text not null check(result in ('success','failed')), amount integer not null check(amount>=0), method text not null default 'simulation', reason text, created_at timestamptz not null default now()
);
create unique index one_payment on transactions(order_id) where kind='payment' and result='success';
create unique index one_refund on transactions(order_id) where kind='refund' and result='success';
create table public.tickets (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references orders(id), seat_id uuid not null references seats(id),
 code text not null unique default ('VE'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,14))), qr_token uuid not null unique default gen_random_uuid(),
 status text not null default 'valid' check(status in ('valid','used','cancelled')), issued_at timestamptz not null default now(), unique(order_id,seat_id)
);
-- Holds expire lazily on every snapshot/write; no client timer can extend a hold.
create function public.cinema_expire(p_show uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 update orders set status='expired' where showtime_id=p_show and status='pending' and expires_at<=now();
 update holds set status='expired' where showtime_id=p_show and status='active' and expires_at<=now();
 update show_seats set status='available',hold_id=null,order_id=null,expires_at=null
 where showtime_id=p_show and status='held' and expires_at<=now();
end $$;
create function public.cinema_seatmap(p_show uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_show::text,0)); perform cinema_expire(p_show);
 if not exists(select 1 from showtimes s join movies m on m.id=s.movie_id where s.id=p_show and m.status<>'stopped') and not cinema_staff() then raise exception 'Không tìm thấy suất chiếu.'; end if;
 select jsonb_build_object('server_now',now(),'seats',coalesce(jsonb_agg(jsonb_build_object('id',g.id,'label',g.label,'row_no',g.row_no,'col_no',g.col_no,'kind',g.kind,'status',s.status,'mine',coalesce(h.user_id=auth.uid(),false),'own_hold',case when h.user_id=auth.uid() then h.id else null end,'expires_at',s.expires_at) order by g.row_no,g.col_no),'[]'::jsonb)) into result
 from show_seats s join seats g on g.id=s.seat_id left join holds h on h.id=s.hold_id where s.showtime_id=p_show;
 return result;
end $$;
create function public.cinema_hold(p_show uuid,p_seats uuid[]) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare s showtimes; v_hold uuid; v_until timestamptz; v_total integer;
begin
 perform cinema_customer(); perform pg_advisory_xact_lock(hashtextextended(p_show::text,0)); perform cinema_expire(p_show);
 select * into s from showtimes where id=p_show;
 if s.id is null or s.status<>'open' or s.starts_at<=now()+interval '15 minutes' or not exists(select 1 from movies where id=s.movie_id and status<>'stopped') or not exists(select 1 from rooms where id=s.room_id and status='active') then raise exception 'Suất chiếu đã đóng bán hoặc không còn khả dụng.'; end if;
 if coalesce(cardinality(p_seats),0) not between 1 and 8 or cardinality(p_seats)<>(select count(distinct x) from unnest(p_seats) x) then raise exception 'Vui lòng chọn từ 1 đến 8 đơn vị ghế khác nhau.'; end if;
 if (select count(*) from show_seats where showtime_id=p_show and seat_id=any(p_seats) and status='available')<>cardinality(p_seats) then raise exception 'Một số ghế vừa được người khác giữ. Vui lòng chọn lại.'; end if;
 if exists(select 1 from holds where user_id=auth.uid() and showtime_id=p_show and status='active') then raise exception 'Bạn đang có phiên giữ ghế. Hãy tiếp tục hoặc trả ghế trước khi chọn lại.'; end if;
 select sum(floor(s.base_price * case kind when 'vip' then 1.2 when 'couple' then 2 else 1 end)) into v_total from seats where id=any(p_seats);
 v_until:=now()+interval '10 minutes';
 insert into holds(user_id,showtime_id,expires_at,quoted_total) values(auth.uid(),p_show,v_until,v_total) returning id into v_hold;
 update show_seats set status='held',hold_id=v_hold,expires_at=v_until where showtime_id=p_show and seat_id=any(p_seats);
 return jsonb_build_object('id',v_hold,'expires_at',v_until,'quoted_total',v_total,'server_now',now());
end $$;
create function public.cinema_release(p_hold uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare h holds;
begin
 select * into h from holds where id=p_hold and user_id=auth.uid(); if h.id is null then raise exception 'Không tìm thấy phiên giữ ghế.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(h.showtime_id::text,0));
 update holds set status='released' where id=p_hold and status='active';
 update show_seats set status='available',hold_id=null,expires_at=null where hold_id=p_hold and order_id is null;
end $$;
create function public.cinema_order(p_hold uuid,p_expected integer) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare h holds; s showtimes; v_total integer; v_id uuid; old_id uuid;
begin
 perform cinema_customer(); select * into h from holds where id=p_hold and user_id=auth.uid();
 if h.id is null then raise exception 'Không tìm thấy phiên giữ ghế.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(h.showtime_id::text,0)); perform cinema_expire(h.showtime_id);
 select id into old_id from orders where hold_id=p_hold; if old_id is not null then return jsonb_build_object('id',old_id); end if;
 select * into h from holds where id=p_hold;
 if h.status<>'active' or h.expires_at<=now() then raise exception 'Đã hết thời gian giữ ghế. Vui lòng chọn lại.'; end if;
 select * into s from showtimes where id=h.showtime_id;
 if s.status='stopped' then raise exception 'Suất chiếu đã ngừng.'; end if;
 select sum(floor(s.base_price * case g.kind when 'vip' then 1.2 when 'couple' then 2 else 1 end)) into v_total from show_seats ss join seats g on g.id=ss.seat_id where ss.hold_id=p_hold;
 if v_total is distinct from p_expected then return jsonb_build_object('price_changed',true,'total',v_total); end if;
 insert into orders(user_id,showtime_id,hold_id,subtotal,total,expires_at,movie_title,room_name,show_starts_at,show_format)
 select auth.uid(),s.id,p_hold,v_total,v_total,now()+interval '10 minutes',m.title,r.name,s.starts_at,s.format from movies m, rooms r where m.id=s.movie_id and r.id=s.room_id returning id into v_id;
 insert into order_items(order_id,seat_id,label,kind,price) select v_id,g.id,g.label,g.kind,floor(s.base_price*case g.kind when 'vip' then 1.2 when 'couple' then 2 else 1 end) from show_seats ss join seats g on g.id=ss.seat_id where ss.hold_id=p_hold;
 update holds set status='converted' where id=p_hold;
 update show_seats set order_id=v_id,expires_at=now()+interval '10 minutes' where hold_id=p_hold;
 return jsonb_build_object('id',v_id);
end $$;
create function public.cinema_promo_discount(p promotions,p_subtotal integer) returns integer language plpgsql as $$
begin
 if p.id is null then raise exception 'Mã khuyến mãi không hợp lệ.'; end if;
 if p.status<>'active' then raise exception 'Chương trình đang tạm dừng hoặc đã ngừng.'; end if;
 if p.starts_at>now() then raise exception 'Chương trình chưa bắt đầu.'; end if;
 if p.ends_at<now() then raise exception 'Mã khuyến mãi đã hết hạn.'; end if;
 if p.used_count>=p.max_uses then raise exception 'Mã khuyến mãi đã hết lượt sử dụng.'; end if;
 if p_subtotal<p.min_order then raise exception 'Đơn chưa đạt mức tối thiểu % đồng.',p.min_order; end if;
 return least(p_subtotal,case when p.kind='fixed' then p.value else least(floor(p_subtotal::numeric*p.value/100)::integer,p.max_discount) end);
end $$;
create function public.cinema_promo(p_order uuid,p_code text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare o orders; p promotions; v_discount integer:=0;
begin
 perform cinema_customer(); select * into o from orders where id=p_order and user_id=auth.uid();
 if o.id is null then raise exception 'Không tìm thấy đơn.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(o.showtime_id::text,0)); perform cinema_expire(o.showtime_id);
 select * into o from orders where id=p_order for update;
 if o.status<>'pending' or o.expires_at<=now() then raise exception 'Đơn không còn trong thời hạn thanh toán.'; end if;
 if trim(coalesce(p_code,''))<>'' then select * into p from promotions where code=upper(trim(p_code)); v_discount:=cinema_promo_discount(p,o.subtotal); end if;
 update orders set promotion_id=p.id,promotion_code=p.code,discount=v_discount,total=subtotal-v_discount where id=p_order;
 return jsonb_build_object('total',o.subtotal-v_discount,'discount',v_discount);
end $$;
-- Explicit simulation provider, no VNPay endpoint/credentials are used.
create table public.cinema_settings (id boolean primary key default true check(id), simulation_enabled boolean not null default true, simulation_outcome text not null default 'success' check(simulation_outcome in ('success','failed','timeout')));
insert into cinema_settings(id) values(true);
create function public.cinema_pay(p_order uuid,p_expected integer) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare o orders; p promotions; d integer; why text; outcome text;
begin
 perform cinema_customer(); select * into o from orders where id=p_order and user_id=auth.uid();
 if o.id is null then raise exception 'Không tìm thấy đơn.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(o.showtime_id::text,0)); perform cinema_expire(o.showtime_id);
 select * into o from orders where id=p_order for update;
 if o.status='paid' then return jsonb_build_object('paid',true); end if;
 if o.status<>'pending' or o.expires_at<=now() then raise exception 'Đơn đã hết hạn hoặc không thể thanh toán.'; end if;
 if not exists(select 1 from cinema_settings where id and simulation_enabled) then raise exception 'Thanh toán mô phỏng đang tắt. VNPay chưa được tích hợp.'; end if;
 if (select count(*) from show_seats where order_id=o.id and status='held')<>(select count(*) from order_items where order_id=o.id) then raise exception 'Ghế không còn được giữ cho đơn. Vui lòng kiểm tra lại.'; end if;
 if o.promotion_id is not null then
  select * into p from promotions where id=o.promotion_id for update;
  begin d:=cinema_promo_discount(p,o.subtotal); exception when others then why:=sqlerrm; d:=0; end;
  if why is not null or d<>o.discount then
   update orders set promotion_id=case when why is null then p.id else null end,promotion_code=case when why is null then p.code else null end,discount=d,total=subtotal-d where id=o.id;
   return jsonb_build_object('price_changed',true,'total',o.subtotal-d,'reason',coalesce(why,'Giá trị khuyến mãi đã thay đổi.'));
  end if;
 end if;
 if p_expected<>o.total then return jsonb_build_object('price_changed',true,'total',o.total,'reason','Vui lòng xác nhận tổng tiền hiện tại.'); end if;
 select simulation_outcome into outcome from cinema_settings where id;
 if outcome<>'success' then
  insert into transactions(order_id,kind,result,amount,reason) values(o.id,'payment','failed',o.total,case outcome when 'timeout' then 'Quá thời gian phản hồi 30 giây (mô phỏng)' else 'Thanh toán không thành công (mô phỏng)' end);
  return jsonb_build_object('paid',false,'reason',case outcome when 'timeout' then 'Thanh toán không thành công do quá thời gian phản hồi.' else 'Thanh toán chưa thành công. Bạn có thể thử lại khi đơn còn hạn.' end);
 end if;
 insert into transactions(order_id,kind,result,amount) values(o.id,'payment','success',o.total);
 update orders set status='paid',paid_at=now() where id=o.id;
 update show_seats set status='sold',expires_at=null where order_id=o.id;
 if o.promotion_id is not null then update promotions set used_count=used_count+1 where id=o.promotion_id; end if;
 insert into tickets(order_id,seat_id) select o.id,seat_id from order_items where order_id=o.id;
 return jsonb_build_object('paid',true);
end $$;
create function public.cinema_cancel_internal(p_order uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare o orders;
begin
 select * into o from orders where id=p_order for update;
 if o.status='paid' then
  insert into transactions(order_id,kind,result,amount) values(o.id,'refund','success',o.total);
  update orders set status='cancelled',cancelled_at=now() where id=o.id;
  update tickets set status='cancelled' where order_id=o.id;
  update show_seats set status='available',hold_id=null,order_id=null,expires_at=null where order_id=o.id;
 end if;
end $$;
create function public.cinema_cancel(p_order uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare o orders;
begin
 select * into o from orders where id=p_order and (user_id=auth.uid() or cinema_staff()); if o.id is null then raise exception 'Không tìm thấy đơn.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(o.showtime_id::text,0)); select * into o from orders where id=p_order for update;
 if o.status='cancelled' then return jsonb_build_object('cancelled',true,'refund',o.total); end if;
 if o.status<>'paid' or o.show_starts_at<now()+interval '2 hours' then raise exception 'Chỉ có thể hủy đơn đã thanh toán khi còn ít nhất 2 giờ trước giờ chiếu.'; end if;
 if exists(select 1 from tickets where order_id=o.id and status='used') then raise exception 'Không thể hủy đơn có vé đã sử dụng.'; end if;
 perform cinema_cancel_internal(o.id); return jsonb_build_object('cancelled',true,'refund',o.total);
end $$;
create function public.cinema_stop_show(p_show uuid,p_expected jsonb) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare impact jsonb; o record; historical boolean;
begin
 if not cinema_staff() then raise exception 'Bạn không có quyền quản trị.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_show::text,0)); perform cinema_expire(p_show);
 if not exists(select 1 from showtimes where id=p_show) then raise exception 'Không tìm thấy suất chiếu.'; end if;
 select jsonb_build_object('paid',count(*) filter(where status='paid'),'pending',count(*) filter(where status='pending'),'refund',coalesce(sum(total) filter(where status='paid'),0),'tickets',(select count(*) from tickets t join orders x on x.id=t.order_id where x.showtime_id=p_show and t.status<>'cancelled'),'holds',(select count(*) from holds where showtime_id=p_show and status='active')) into impact from orders where showtime_id=p_show;
 if p_expected is null or impact<>p_expected then return jsonb_build_object('confirm',true,'impact',impact); end if;
 select exists(select 1 from orders where showtime_id=p_show) or exists(select 1 from holds where showtime_id=p_show) into historical;
 if not historical then delete from showtimes where id=p_show; return jsonb_build_object('deleted',true); end if;
 for o in select id from orders where showtime_id=p_show and status='paid' order by id loop perform cinema_cancel_internal(o.id); end loop;
 update orders set status='expired' where showtime_id=p_show and status='pending';
 update holds set status='released' where showtime_id=p_show and status='active';
 update show_seats set status='available',hold_id=null,order_id=null,expires_at=null where showtime_id=p_show;
 update showtimes set status='stopped' where id=p_show;
 return jsonb_build_object('stopped',true,'impact',impact);
end $$;
create function public.cinema_admin_save(p_entity text,p_data jsonb) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid()); v_movie movies; v_room rooms; v_show showtimes; v_promo promotions; v_start timestamptz; v_end timestamptz; v_room_id uuid; busy boolean; n integer; x jsonb;
begin
 if not cinema_staff() then raise exception 'Bạn không có quyền quản trị.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('cinema_catalog',0));
 if p_entity='movies' then
  select * into v_movie from movies where id=v_id;
  if v_movie.id is not null and (v_movie.duration<>(p_data->>'duration')::integer or (p_data->>'status'='stopped' and v_movie.status<>'stopped')) and exists(select 1 from showtimes where movie_id=v_id and starts_at>now() and status<>'stopped') then raise exception 'Hãy xử lý các suất tương lai trước khi đổi thời lượng hoặc ngừng phim.'; end if;
  insert into movies(id,title,duration,genres,age,language,description,poster_url,trailer_url,director,actors,country,release_date,status)
  values(v_id,trim(p_data->>'title'),(p_data->>'duration')::integer,p_data->>'genres',p_data->>'age',p_data->>'language',coalesce(p_data->>'description',''),coalesce(p_data->>'poster_url',''),coalesce(p_data->>'trailer_url',''),coalesce(p_data->>'director',''),coalesce(p_data->>'actors',''),coalesce(p_data->>'country',''),nullif(p_data->>'release_date','')::date,p_data->>'status')
  on conflict(id) do update set title=excluded.title,duration=excluded.duration,genres=excluded.genres,age=excluded.age,language=excluded.language,description=excluded.description,poster_url=excluded.poster_url,trailer_url=excluded.trailer_url,director=excluded.director,actors=excluded.actors,country=excluded.country,release_date=excluded.release_date,status=excluded.status;
 elsif p_entity='rooms' then
  select * into v_room from rooms where id=v_id;
  busy:=exists(select 1 from showtimes where room_id=v_id);
  if busy and ((p_data ? 'seats') or (v_room.status<>'maintenance' and p_data->>'status'='maintenance' and exists(select 1 from showtimes where room_id=v_id and starts_at>now() and status<>'stopped'))) then raise exception 'Phòng đã có suất chiếu. Không thể đổi sơ đồ; hãy xử lý suất trước khi bảo trì.'; end if;
  insert into rooms(id,name,format,status) values(v_id,trim(p_data->>'name'),p_data->>'format',p_data->>'status') on conflict(id) do update set name=excluded.name,format=excluded.format,status=excluded.status;
  if p_data ? 'seats' then
   if jsonb_array_length(p_data->'seats') not between 1 and 600 then raise exception 'Sơ đồ cần từ 1 đến 600 đơn vị ghế.'; end if;
   delete from seats where room_id=v_id;
   for x in select * from jsonb_array_elements(p_data->'seats') loop
    insert into seats(room_id,label,row_no,col_no,kind) values(v_id,x->>'label',(x->>'row_no')::integer,(x->>'col_no')::integer,x->>'kind');
   end loop;
   if exists(select 1 from seats a join seats b on a.room_id=b.room_id and a.row_no=b.row_no and a.col_no+1=b.col_no where a.room_id=v_id and a.kind='couple') then raise exception 'Ghế đôi chiếm hai vị trí, không được chồng lên ghế khác.'; end if;
  end if;
 elsif p_entity='showtimes' then
  perform pg_advisory_xact_lock(hashtextextended(v_id::text,0));
  select * into v_show from showtimes where id=v_id;
  busy:=exists(select 1 from orders where showtime_id=v_id) or exists(select 1 from holds where showtime_id=v_id);
  if busy then
   if v_show.movie_id::text<>p_data->>'movie_id' or v_show.room_id::text<>p_data->>'room_id' or v_show.starts_at<>(p_data->>'starts_at')::timestamptz or v_show.format<>p_data->>'format' then raise exception 'Suất đã có giao dịch; chỉ được sửa giá cơ bản.'; end if;
   update showtimes set base_price=(p_data->>'base_price')::integer where id=v_id; return v_id;
  end if;
  select * into v_movie from movies where id=(p_data->>'movie_id')::uuid and status<>'stopped';
  v_room_id:=(p_data->>'room_id')::uuid;
  if v_movie.id is null or not exists(select 1 from rooms where id=v_room_id and status='active') or not exists(select 1 from seats where room_id=v_room_id) then raise exception 'Phim/phòng không khả dụng hoặc phòng chưa có sơ đồ.'; end if;
  v_start:=(p_data->>'starts_at')::timestamptz; v_end:=v_start+make_interval(mins=>v_movie.duration+15);
  if v_start<=now() then raise exception 'Giờ chiếu phải ở tương lai.'; end if;
  if exists(select 1 from showtimes where room_id=v_room_id and id<>v_id and status<>'stopped' and starts_at<v_end+interval '15 minutes' and ends_at+interval '15 minutes'>v_start) then raise exception 'Lịch chiếu xung đột. Cần đủ 15 phút quảng cáo và 15 phút dọn phòng giữa hai suất.'; end if;
  insert into showtimes(id,movie_id,room_id,starts_at,ends_at,format,base_price) values(v_id,v_movie.id,v_room_id,v_start,v_end,p_data->>'format',(p_data->>'base_price')::integer)
  on conflict(id) do update set movie_id=excluded.movie_id,room_id=excluded.room_id,starts_at=excluded.starts_at,ends_at=excluded.ends_at,format=excluded.format,base_price=excluded.base_price;
  delete from show_seats where showtime_id=v_id;
  insert into show_seats(showtime_id,seat_id) select v_id,id from seats where room_id=v_room_id;
 elsif p_entity='promotions' then
  select * into v_promo from promotions where id=v_id for update;
  if (p_data->>'max_uses')::integer<coalesce(v_promo.used_count,0) then raise exception 'Số lượt tối đa không được nhỏ hơn số đã dùng.'; end if;
  insert into promotions(id,code,name,kind,value,max_discount,min_order,starts_at,ends_at,max_uses,status)
  values(v_id,upper(trim(p_data->>'code')),p_data->>'name',p_data->>'kind',(p_data->>'value')::integer,(p_data->>'max_discount')::integer,(p_data->>'min_order')::integer,(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,(p_data->>'max_uses')::integer,p_data->>'status')
  on conflict(id) do update set code=excluded.code,name=excluded.name,kind=excluded.kind,value=excluded.value,max_discount=excluded.max_discount,min_order=excluded.min_order,starts_at=excluded.starts_at,ends_at=excluded.ends_at,max_uses=excluded.max_uses,status=excluded.status;
 else raise exception 'Danh mục không hợp lệ.';
 end if;
 return v_id;
end $$;
-- Every table is protected. Clients receive no direct insert/update/delete grants.
do $$ declare t text; begin
 foreach t in array array['profiles','movies','rooms','seats','showtimes','holds','promotions','orders','order_items','show_seats','transactions','tickets','cinema_settings'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon, authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy staff_read on public.%I for select to authenticated using (public.cinema_staff())',t);
 end loop;
end $$;
grant select on movies,rooms,seats,showtimes to anon;
create policy public_movies on movies for select using(status<>'stopped');
create policy public_rooms on rooms for select using(true);
create policy public_seats on seats for select using(true);
create policy public_shows on showtimes for select using(status<>'stopped' and exists(select 1 from movies where movies.id=movie_id and movies.status<>'stopped'));
create policy own_profile on profiles for select using(id=auth.uid());
create policy own_holds on holds for select using(user_id=auth.uid());
create policy own_orders on orders for select using(user_id=auth.uid());
create policy own_items on order_items for select using(exists(select 1 from orders where orders.id=order_id and user_id=auth.uid()));
create policy own_transactions on transactions for select using(exists(select 1 from orders where orders.id=order_id and user_id=auth.uid()));
create policy own_tickets on tickets for select using(exists(select 1 from orders where orders.id=order_id and user_id=auth.uid()));
do $$ declare f record; begin for f in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname like 'cinema_%' loop execute format('revoke all on function %s from public,anon,authenticated',f.sig); end loop; end $$;
grant execute on function cinema_staff() to anon,authenticated;
grant execute on function cinema_seatmap(uuid) to anon,authenticated;
grant execute on function cinema_hold(uuid,uuid[]),cinema_release(uuid),cinema_order(uuid,integer),cinema_promo(uuid,text),cinema_pay(uuid,integer),cinema_cancel(uuid),cinema_stop_show(uuid,jsonb),cinema_admin_save(text,jsonb) to authenticated;
commit;
