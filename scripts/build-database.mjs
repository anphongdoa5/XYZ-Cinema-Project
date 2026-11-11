import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildDeploy} from './build-deploy.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=file=>fs.readFileSync(path.join(root,file),'utf8').trim();
const write=(file,text)=>fs.writeFileSync(path.join(root,file),text+'\n');
const files=fs.readdirSync(path.join(root,'supabase/schema')).filter(name=>/^0[1-6]-.*\.sql$/.test(name)).sort();
const sources=files.map(file=>read('supabase/schema/'+file));
const gateway=read('supabase/schema/08-vnpay.sql');
const [gatewayTables,gatewayRest]=gateway.split('-- BEGIN RPC');
const [gatewayRpc,gatewayActivation]=gatewayRest.split('-- BEGIN ACTIVATION');
const schema=[sources[0],gatewayTables,...sources.slice(1),gatewayRpc].join('\n\n'),seed=read('supabase/schema/07-seed.sql');
const header='-- XYZ Cinema · Chương 3, Bảng 3.1–3.17.\n-- Sinh bằng node scripts/build-database.mjs; nguồn trong supabase/schema/.\n';
// Baseline đã phát hành được giữ nguyên; thay đổi dùng migration kế tiếp.
if(!fs.existsSync(path.join(root,'supabase/migrations/202611090001_chapter3.sql')))write('supabase/migrations/202611090001_chapter3.sql',header+'begin;\n'+schema+'\ncommit;');
write('supabase/seed.sql',"-- Bổ sung dữ liệu khi đã có cấu trúc.\nbegin;\nset local search_path=public,extensions,pg_temp;\n"+seed+'\ncommit;');
write('supabase/install.sql',header+`-- CÀI MỚI: cấu trúc + dữ liệu mẫu. Không chạy trên database đã có dữ liệu.
-- Nếu đã cài Chương 3, chạy supabase/upgrade.sql để cập nhật và giữ dữ liệu.
begin;
do $$ begin
 if to_regclass('public.profiles') is not null or to_regclass('public.movies') is not null or to_regclass('public.khach_hang') is not null then
  raise exception 'Đã có cấu trúc. Dừng cài mới. Nếu đã cài Chương 3, chạy supabase/upgrade.sql; không reset dữ liệu đang dùng.';
 end if;
end $$;
`+schema+'\n\n-- DỮ LIỆU MẪU\n'+seed+'\n'+gatewayActivation+'\ncommit;\n\n'+read('supabase/verify.sql'));
const tables=['khach_hang','nhan_vien','the_loai','phim','phim_the_loai','phong_chieu','loai_ghe','ghe','suat_chieu','ghe_suat_chieu','don_dat_ve','ve','khuyen_mai','phuong_thuc_thanh_toan','thanh_toan'];
const literal=values=>values.map(value=>"'"+value+"'").join(',');
const functions=[...schema.matchAll(/create function public\.[\s\S]*?\$\$;/g)].map(match=>match[0].replace('create function','create or replace function')).join('\n\n');
const policyNames=['staff_read',...[...sources.at(-1).matchAll(/create policy (\w+) on/g)].map(match=>match[1])];
const upgrade=header+`-- CẬP NHẬT CHƯƠNG 3: giữ tài khoản, mật khẩu, đơn, vé, thu/hoàn và dữ liệu mẫu.
-- Dán TOÀN BỘ tệp vào SQL Editor rồi Run. Không chạy reset.sql trước tệp này.
begin;
set local search_path=public,extensions,pg_temp;
do $$ begin
 perform pg_advisory_xact_lock(hashtextextended('xyz_cinema_install',0));
 if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=any(array[${literal(tables)}]) and c.relkind='r')<>15 or to_regclass('cinema_private.cau_hinh') is null then
  raise exception 'Chưa có đủ cấu trúc Chương 3. Dừng cập nhật, không thay đổi dữ liệu. Xem supabase/README.md.';
 end if;
 if not exists(select 1 from cinema_private.cau_hinh where id and schema_version in ('chapter3-custom-auth-v1','chapter3-audit-v2')) then
  raise exception 'Phiên bản database chưa được nhận diện. Dừng cập nhật để kiểm tra.';
 end if;
end $$;
${gatewayTables}
${functions}
${gatewayRpc}
${gatewayActivation}

-- Cập nhật các chính sách đã biết trong một giao dịch; không xóa bảng.
do $$ declare p record; begin
 for p in select schemaname,tablename,policyname from pg_policies where schemaname='public' and tablename=any(array[${literal(tables)}]) and policyname=any(array[${literal(policyNames)}]) loop
  execute format('drop policy %I on %I.%I',p.policyname,p.schemaname,p.tablename);
 end loop;
end $$;
${sources.at(-1)}

-- Lưu mã khuyến mãi tại thời điểm nâng cấp cho các đơn cũ chưa có snapshot mã.
update cinema_private.don_snapshot x set du_lieu=x.du_lieu||jsonb_build_object('promotion_code',p.ma_khuyen_mai)
from don_dat_ve d left join khuyen_mai p using(khuyen_mai_id)
where x.don_dat_ve_id=d.don_dat_ve_id and not (x.du_lieu ? 'promotion_code');
create index if not exists cinema_inventory_expiry on public.ghe_suat_chieu(suat_chieu_id,thoi_gian_giu_den) where trang_thai='GIU';
create index if not exists cinema_snapshot_show on cinema_private.don_snapshot(suat_chieu_id);
create index if not exists cinema_transactions_order on public.thanh_toan(don_dat_ve_id,loai_giao_dich,trang_thai);
create index if not exists cinema_tickets_order on public.ve(don_dat_ve_id);
create index if not exists cinema_session_expiry on cinema_private.phien_dang_nhap(het_han);
update cinema_private.cau_hinh set schema_version='chapter3-audit-v2' where id;
notify pgrst,'reload schema';
commit;
select public.cinema_version() as phien_ban;
`;
write('supabase/upgrade.sql',upgrade);
if(!fs.existsSync(path.join(root,'supabase/migrations/202611090002_stability.sql')))write('supabase/migrations/202611090002_stability.sql',upgrade);
const catalogFunction=sources[3].match(/create function public\.cinema_catalog\(\)[\s\S]*?\$\$;/)?.[0];
if(!catalogFunction)throw new Error('Missing cinema_catalog source');
const weeklyFeature=header+`-- CẬP NHẬT TÂM ĐIỂM THEO VÉ BÁN TRONG TUẦN. Không reset/cài lại database.
-- Chỉ thay hàm đọc catalog; giữ nguyên bảng, cột, tài khoản, đơn, vé và giao dịch.
begin;
set local search_path=public,extensions,pg_temp;
do $$ begin
 perform pg_advisory_xact_lock(hashtextextended('xyz_cinema_install',0));
 if to_regprocedure('public.cinema_catalog()') is null or to_regclass('public.ve') is null then
  raise exception 'Cần cài database Chương 3 trước khi cập nhật Tâm điểm.';
 end if;
end $$;
${catalogFunction.replace('create function','create or replace function')}
notify pgrst,'reload schema';
commit;
select 'weekly-feature-v1' as cap_nhat;
`;
write('supabase/update-weekly-feature.sql',weeklyFeature);
if(!fs.existsSync(path.join(root,'supabase/migrations/202611090003_weekly_feature.sql')))write('supabase/migrations/202611090003_weekly_feature.sql',weeklyFeature);
console.log('Generated install/seed/upgrade; preserved published baseline migration.');

// Nâng cấp VNPay giữ dữ liệu, chỉ thay các hàm đã biết.
const changed=['cinema_pay','cinema_promo_discount','cinema_promo','cinema_order_json'];
const gatewayDependencies=[...sources.join('\n').matchAll(/create function public\.(\w+)\([\s\S]*?\$\$;/g)].filter(m=>changed.includes(m[1])).map(m=>m[0].replace('create function','create or replace function')).join('\n\n');
const vnpay=header+"-- Nâng cấp VNPay Sandbox giữ dữ liệu. Không chạy reset/install trước tệp này.\nbegin;\nset local search_path=public,extensions,pg_temp;\nselect pg_advisory_xact_lock(hashtextextended('xyz_cinema_install',0));\n"+gatewayTables+'\n'+gatewayDependencies+'\n'+gatewayRpc+'\n'+gatewayActivation+"\nnotify pgrst,'reload schema';\ncommit;\nselect 'vnpay-sandbox-v1' as cap_nhat;";
write('supabase/enable-vnpay.sql',vnpay);
if(!fs.existsSync(path.join(root,'supabase/migrations/202611100004_vnpay_sandbox.sql')))write('supabase/migrations/202611100004_vnpay_sandbox.sql',vnpay);
const confirmation=header+"-- Sửa xác nhận VNPay; giữ tài khoản, đơn, ghế, vé và giao dịch. Không reset/cài lại.\nbegin;\nset local search_path=public,extensions,pg_temp;\nselect pg_advisory_xact_lock(hashtextextended('xyz_cinema_install',0));\n"+gatewayTables+'\n'+gatewayRpc+"\nnotify pgrst,'reload schema';\ncommit;\nselect 'vnpay-confirmation-v2' as cap_nhat;";
write('supabase/fix-vnpay-confirmation.sql',confirmation);
if(!fs.existsSync(path.join(root,'supabase/migrations/202611100005_vnpay_confirmation.sql')))write('supabase/migrations/202611100005_vnpay_confirmation.sql',confirmation);
buildDeploy(root);
console.log('Generated supabase/deploy.sql: one SQL Editor entry point for fresh install or upgrade.');
