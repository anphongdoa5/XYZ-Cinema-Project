-- Kiểm tra 15 bảng, kiểu khóa và ràng buộc sau khi cài Chương 3.
select c.table_name as bang,count(*) as so_cot from information_schema.columns c
where c.table_schema='public' and c.table_name in ('khach_hang','nhan_vien','the_loai','phim','phim_the_loai','phong_chieu','loai_ghe','ghe','suat_chieu','ghe_suat_chieu','don_dat_ve','ve','khuyen_mai','phuong_thuc_thanh_toan','thanh_toan')
group by c.table_name order by c.table_name;
select 'Phim' as hang_muc,count(*)::text as ket_qua from public.phim
union all select 'Thể loại',count(*)::text from public.the_loai
union all select 'Liên kết phim-thể loại',count(*)::text from public.phim_the_loai
union all select 'Phòng chiếu',count(*)::text from public.phong_chieu
union all select 'Loại ghế',count(*)::text from public.loai_ghe
union all select 'Đơn vị ghế',count(*)::text from public.ghe
union all select 'Chỗ ngồi',sum(suc_chua)::text from public.phong_chieu
union all select 'Suất còn mở bán',count(*)::text from public.suat_chieu where trang_thai='DANG_MO_BAN' and thoi_gian_bat_dau>now()+interval '15 minutes'
union all select 'Ghế theo suất',count(*)::text from public.ghe_suat_chieu
union all select 'Mã khuyến mãi',count(*)::text from public.khuyen_mai
union all select 'Phương thức thanh toán',count(*)::text from public.phuong_thuc_thanh_toan;
select c.relname as bang,c.relrowsecurity as da_bat_rls,count(p.polname) as so_chinh_sach
from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_policy p on p.polrelid=c.oid
where n.nspname='public' and c.relname in ('khach_hang','nhan_vien','the_loai','phim','phim_the_loai','phong_chieu','loai_ghe','ghe','suat_chieu','ghe_suat_chieu','don_dat_ve','ve','khuyen_mai','phuong_thuc_thanh_toan','thanh_toan')
group by c.relname,c.relrowsecurity order by c.relname;
