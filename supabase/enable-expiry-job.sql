-- Chạy một lần trong Supabase SQL Editor (DB owner) để thực thi BR02/BR13 định kỳ.
-- Có thể bật pg_cron trong Database → Extensions trước khi chạy.
create extension if not exists pg_cron;
select cron.schedule('xyz-cinema-expire','* * * * *','select public.cinema_expire_all();');
select jobid,jobname,schedule,active from cron.job where jobname='xyz-cinema-expire';
