-- Bổ sung dữ liệu khi đã có cấu trúc.
begin;
set local search_path=public,extensions,pg_temp;
-- Dữ liệu mẫu theo 15 bảng Chương 3; không tạo tài khoản Auth/mật khẩu mẫu.
insert into nhan_vien(nhan_vien_id,ho_ten,email,vai_tro,ten_dang_nhap,mat_khau)
values(1,'Nhân viên khởi tạo dữ liệu','seed@xyz-cinema.invalid','NHAN_VIEN','du_lieu_mau',crypt(encode(gen_random_bytes(32),'hex'),gen_salt('bf',12))) on conflict(nhan_vien_id) do nothing;
insert into the_loai(the_loai_id,ten_the_loai) values
(1,'Khoa học viễn tưởng'),(2,'Tình cảm'),(3,'Gia đình'),(4,'Bí ẩn'),(5,'Giật gân'),(6,'Phiêu lưu'),(7,'Hành động') on conflict(the_loai_id) do nothing;
insert into loai_ghe(loai_ghe_id,ten_loai_ghe,he_so_gia,mo_ta) values
(1,'Thường',1.00,'Một đơn vị, một chỗ'),(2,'VIP',1.20,'Một đơn vị, một chỗ'),(3,'Đôi',2.00,'Một đơn vị gồm hai chỗ liền kề, không bán tách lẻ') on conflict(loai_ghe_id) do nothing;
insert into phim(phim_id,ten_phim,thoi_luong,do_tuoi_gioi_han,ngon_ngu,mo_ta,trang_thai,ngay_khoi_chieu) values
(1,'Chạm đến vì sao',120,13,'Tiếng Anh','Một tín hiệu từ vũ trụ. Một hành trình tìm về những điều thân thuộc.','DANG_CHIEU',(now() at time zone 'Asia/Ho_Chi_Minh')::date-7),
(2,'Mùa nắng đi qua',105,0,'Tiếng Việt','Những người bạn cũ gặp lại trong một mùa hè không thể quên.','DANG_CHIEU',(now() at time zone 'Asia/Ho_Chi_Minh')::date-3),
(3,'Phía sau cánh cửa',110,16,'Tiếng Việt','Một bí mật bị che giấu, một cánh cửa không nên mở.','DANG_CHIEU',(now() at time zone 'Asia/Ho_Chi_Minh')::date-1),
(4,'Dũng: Hành trình cát – Phần 3',90,0,'Tiếng Việt','Chuyến phiêu lưu qua những miền cát và những điều kỳ diệu.','SAP_CHIEU',(now() at time zone 'Asia/Ho_Chi_Minh')::date+7),
(5,'Ngày tận thế',115,18,'Tiếng Anh','Một nhóm người tìm lại hy vọng giữa những thay đổi của thế giới.','SAP_CHIEU',(now() at time zone 'Asia/Ho_Chi_Minh')::date+10),
(6,'Bác sĩ X: Mật mã trắng',115,16,'Tiếng Việt','Hành trình tìm lời giải cho những sự kiện bất thường.','SAP_CHIEU',(now() at time zone 'Asia/Ho_Chi_Minh')::date+12)
on conflict(phim_id) do nothing;
insert into phim_the_loai(phim_id,the_loai_id) values(1,1),(2,2),(2,3),(3,4),(3,5),(4,6),(5,7),(6,4) on conflict do nothing;
insert into phong_chieu(phong_chieu_id,ten_phong,suc_chua) values(1,'Phòng 01',84),(2,'Phòng 02',84),(3,'Phòng 03',84) on conflict(phong_chieu_id) do nothing;
insert into ghe(phong_chieu_id,loai_ghe_id,hang_ghe,so_ghe)
select r.phong_chieu_id,case when a.n=7 then 3 when a.n>=4 then 2 else 1 end,chr(64+a.n),b.n
from phong_chieu r cross join generate_series(1,7) a(n) cross join generate_series(1,12) b(n)
where r.phong_chieu_id in (1,2,3) and (a.n<>7 or b.n%2=1) on conflict do nothing;
with slots as (
 select p.phim_id,r.phong_chieu_id,
 ((((now() at time zone 'Asia/Ho_Chi_Minh')::date)+d.n)::text||' '||h.n||':00:00+07')::timestamptz starts_at,p.thoi_luong
 from phim p join phong_chieu r on r.phong_chieu_id=p.phim_id
 cross join generate_series(0,4) d(n) cross join (values(10),(14),(18),(22)) h(n)
 where p.phim_id in (1,2,3) and p.trang_thai='DANG_CHIEU' and r.trang_thai=1
), inserted as (
 insert into suat_chieu(phim_id,phong_chieu_id,nhan_vien_id,thoi_gian_bat_dau,thoi_gian_ket_thuc,gia_ve_co_ban,ngon_ngu_hien_thi,dinh_dang_chieu,trang_thai)
 select x.phim_id,x.phong_chieu_id,1,x.starts_at,x.starts_at+make_interval(mins=>x.thoi_luong+15),100000,'phụ đề','2D','DANG_MO_BAN' from slots x
 where x.starts_at>now()+interval '15 minutes'
 and not exists(select 1 from suat_chieu s where s.phong_chieu_id=x.phong_chieu_id and s.thoi_gian_bat_dau=x.starts_at)
 and not exists(select 1 from suat_chieu s where s.phong_chieu_id=x.phong_chieu_id and s.trang_thai<>'DA_HUY' and s.thoi_gian_bat_dau<x.starts_at+make_interval(mins=>x.thoi_luong+30) and s.thoi_gian_ket_thuc+interval '15 minutes'>x.starts_at)
 returning suat_chieu_id,phong_chieu_id,gia_ve_co_ban
)
insert into ghe_suat_chieu(suat_chieu_id,ghe_id,trang_thai,gia_ban)
select x.suat_chieu_id,g.ghe_id,'TRONG',floor(x.gia_ve_co_ban*l.he_so_gia) from inserted x join ghe g using(phong_chieu_id) join loai_ghe l using(loai_ghe_id) where g.trang_thai=1;
insert into khuyen_mai(khuyen_mai_id,nhan_vien_id,ma_khuyen_mai,ten_khuyen_mai,hinh_thuc_giam,gia_tri_giam,giam_toi_da,dieu_kien_ap_dung,ngay_bat_dau,ngay_ket_thuc,so_luong_toi_da) values
(1,1,'XYZ10','Ưu đãi trải nghiệm điện ảnh','PHAN_TRAM',10,20000,100000,now()-interval '1 day',now()+interval '30 days',100),
(2,1,'XYZ20K','Giảm 20.000 đồng','SO_TIEN',20000,null,200000,now()-interval '1 day',now()+interval '30 days',50) on conflict(khuyen_mai_id) do nothing;
insert into phuong_thuc_thanh_toan(phuong_thuc_id,ten_phuong_thuc,mo_ta,trang_thai) values
(1,'Thanh toán mô phỏng','Thử luồng đặt vé khi phát triển; không thu tiền thật.',1),
(2,'VNPay Sandbox','Cổng thanh toán thử nghiệm VNPay 2.1.0',1) on conflict(phuong_thuc_id) do nothing;
do $$ declare pair text[]; begin
 foreach pair slice 1 in array array[['nhan_vien','nhan_vien_id'],['the_loai','the_loai_id'],['loai_ghe','loai_ghe_id'],['phim','phim_id'],['phong_chieu','phong_chieu_id'],['khuyen_mai','khuyen_mai_id'],['phuong_thuc_thanh_toan','phuong_thuc_id']] loop
  execute format('select setval(pg_get_serial_sequence(%L,%L),greatest(coalesce(max(%I),0),1),true) from public.%I','public.'||pair[1],pair[2],pair[2],pair[1]);
 end loop;
end $$;
commit;
