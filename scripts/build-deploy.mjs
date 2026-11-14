import fs from 'node:fs';
import path from 'node:path';

/** A self-contained SQL Editor entry point; source fragments remain maintainable. */
export function buildDeploy(root){
 const read=file=>fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n').trim();
 const transactionBody=(file)=>{
  const sql=read(file),start=sql.indexOf('\nbegin;\n'),end=sql.lastIndexOf('\ncommit;');
  if(start<0||end<=start)throw Error('Missing transaction boundaries: '+file);
  return sql.slice(start+'\nbegin;\n'.length,end).trim();
 };
 const quote=(tag,sql)=>{const delimiter='$xyz_'+tag+'$';if(sql.includes(delimiter))throw Error('SQL delimiter collision');return delimiter+'\n'+sql+'\n'+delimiter;};
 const tables=['khach_hang','nhan_vien','the_loai','phim','phim_the_loai','phong_chieu','loai_ghe','ghe','suat_chieu','ghe_suat_chieu','don_dat_ve','ve','khuyen_mai','phuong_thuc_thanh_toan','thanh_toan','nhat_ky_hoat_dong'];
 const names=tables.map(t=>"'"+t+"'").join(',');
 const sql=`-- XYZ CINEMA · TRIỂN KHAI DATABASE BẰNG MỘT TỆP
-- Phiên bản gói: xyz-cinema-three-roles-v3 · 13/11/2026.
-- Supabase SQL Editor → New query → dán TOÀN BỘ tệp → Run (role postgres).
-- Cài mới: đủ cấu trúc, RLS/RPC, dữ liệu mẫu, admin/admin, Tâm điểm, VNPay v2, Cron.
-- Đã cài Chương 3: cập nhật giữ dữ liệu; không nạp lại seed hoặc đổi mật khẩu admin.
-- Không cần chạy install/upgrade/weekly/VNPay/create-dev-admin/expiry-job riêng.
-- Không chứa Supabase/VNPay API keys. Cấu hình website trong .env.local theo HUONG_DAN_CHAY.md.
-- Sinh tự động: node scripts/build-database.mjs. Không sửa riêng tệp được sinh.
begin;
set local search_path=public,extensions,pg_temp;
select pg_advisory_xact_lock(hashtextextended('xyz_cinema_install',0));

-- 1. Tự nhận diện cài mới hoặc cập nhật. Cấu trúc lạ/dở dang sẽ dừng, không xóa dữ liệu.
do $xyz_deploy$
declare business_count integer;
begin
 if exists(select 1 from unnest(array['anon','authenticated','service_role']) r(name)
  where not exists(select 1 from pg_roles p where p.rolname=r.name)) then
  raise exception 'Tệp triển khai dành cho Supabase. Mở SQL Editor của project và chọn role postgres.';
 end if;
 if to_regclass('public.profiles') is not null or to_regclass('public.movies') is not null then
  raise exception 'Phát hiện database XYZ Cinema tiếng Anh cũ. Dừng để giữ dữ liệu; không tự reset hoặc chuyển đổi dữ liệu.';
 end if;
 select count(*) into business_count from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relname=any(array[${names}]) and c.relkind='r';
 if business_count=0 and to_regnamespace('cinema_private') is null then
  execute ${quote('fresh',transactionBody('supabase/install.sql'))};
  raise notice 'XYZ Cinema: đã cài mới cấu trúc, tính năng và dữ liệu mẫu.';
 elsif business_count in (15,16) and to_regclass('cinema_private.cau_hinh') is not null then
  execute ${quote('upgrade',transactionBody('supabase/upgrade.sql'))};
  raise notice 'XYZ Cinema: đã cập nhật tính năng; giữ dữ liệu và tài khoản hiện có.';
 else
  raise exception 'Cấu trúc database thiếu hoặc không nhận diện được. Dừng và giữ dữ liệu; không tự reset. Cần database Supabase mới hoặc đủ bảng Chương 3.';
 end if;
end $xyz_deploy$;

-- 2. Tài khoản phục vụ báo cáo; chỉ tạo khi chưa có, không đặt lại tài khoản đang dùng.
do $xyz_admin$
declare matches integer;
begin
 perform pg_advisory_xact_lock(hashtextextended('xyz_cinema_dev_admin',0));
 select count(*) into matches from public.nhan_vien where lower(ten_dang_nhap)='admin';
 if matches>1 then raise exception 'Có nhiều tài khoản trùng tên admin. Dừng để kiểm tra, không tự sửa tài khoản.'; end if;
 if matches=0 then
  if exists(select 1 from public.nhan_vien where lower(email)='dev-admin@xyz-cinema.test') then
   raise exception 'Email mẫu admin đã thuộc tài khoản khác. Dừng để tránh ghi đè tài khoản.';
  end if;
  insert into public.nhan_vien(ho_ten,email,vai_tro,ten_dang_nhap,mat_khau,trang_thai)
  values('Quản trị viên demo','dev-admin@xyz-cinema.test','QUAN_TRI','admin',crypt('admin',gen_salt('bf',12)),1);
  raise notice 'Đã tạo tài khoản báo cáo: admin / admin, đăng nhập tại /admin/login.';
 else
  raise notice 'Tài khoản admin đã tồn tại: giữ mật khẩu, vai trò, trạng thái và phiên đăng nhập.';
 end if;
end $xyz_admin$;

-- 3. Bật Cron và đặt đúng một công việc quét hết hạn mỗi phút.
-- Không xóa extension hoặc sửa tác vụ của ứng dụng khác.
do $xyz_cron$
declare job_id bigint;
begin
 if to_regprocedure('cron.schedule(text,text,text)') is null then
  begin
   execute 'create extension if not exists pg_cron';
  exception when others then
   raise exception 'Không bật được pg_cron: %. Chạy bằng role postgres trên Supabase; kiểm tra Integrations → Cron rồi chạy lại CHÍNH tệp deploy.sql. Gói chưa được commit.',sqlerrm;
  end;
 end if;
 select cron.schedule('xyz-cinema-expire','* * * * *','select public.cinema_expire_all();') into job_id;
 perform cron.alter_job(job_id,active=>true);
 if not exists(select 1 from cron.job j where j.jobid=job_id and j.active and j.schedule='* * * * *'
  and j.command='select public.cinema_expire_all();') then raise exception 'Chưa đăng ký được tác vụ quét hết hạn.'; end if;
end $xyz_cron$;

notify pgrst,'reload schema';
commit;

-- 4. Kết quả cuối: thấy xyz-cinema-three-roles-v3 và các mục kiểm tra là true.
select 'xyz-cinema-three-roles-v3' as ket_qua,
 (select count(*)::integer from pg_tables where schemaname='public' and tablename=any(array[${names}])) as bang_nghiep_vu,
 not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname=any(array[${names}]) and not c.relrowsecurity) as rls_day_du,
 to_regprocedure('public.cinema_catalog()') is not null as tam_diem_tuan,
 to_regprocedure('public.cinema_vnpay_query_attempt(bigint,bigint)') is not null as vnpay_confirmation_v2,
 exists(select 1 from public.nhan_vien where lower(ten_dang_nhap)='admin') as co_tai_khoan_admin,
 (select count(*)::int from public.nhan_vien where vai_tro='NHAN_VIEN' and trang_thai=1) as so_nhan_vien,
 exists(select 1 from cron.job where jobname='xyz-cinema-expire' and username=current_user and database=current_database() and active) as cron_het_han,
 (select count(*)::integer from public.phim) as so_phim,
 (select count(*)::integer from public.phong_chieu) as so_phong,
 (select count(*)::integer from public.suat_chieu where trang_thai='DANG_MO_BAN' and thoi_gian_bat_dau>now()+interval '15 minutes') as suat_con_mo_ban;
`;
 fs.writeFileSync(path.join(root,'supabase/deploy.sql'),sql);
 return sql;
}
