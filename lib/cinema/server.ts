import 'server-only';
import { createClient } from '@/lib/supabase/server';
import type {Profile} from './types';
import type {SessionScope} from './session';
export async function identity(client?:Awaited<ReturnType<typeof createClient>>,scope:SessionScope='customer'){
 const db=client??await createClient(scope);const {data,error}=await db.rpc('cinema_profile');databaseError(error);
 const candidate=data as Profile|null;const profile=candidate?.role===(scope==='admin'?'staff':'customer')?candidate:null;return {db,user:profile?{id:profile.id}:null,profile};
}
export function databaseError(error:{message:string;code?:string}|null){
 if(!error)return;
 if(/fetch failed|network|aborted|timeout/i.test(error.message))throw new Error('Chưa kết nối được Supabase. Kiểm tra Project URL, Publishable key và kết nối mạng, rồi thử lại.');
 if(['42P01','PGRST205','PGRST202'].includes(error.code||''))throw new Error('Cơ sở dữ liệu chưa sẵn sàng. Hãy chạy supabase/deploy.sql trong Supabase SQL Editor.');
 if(error.code==='23505')throw new Error('Thông tin đã tồn tại. Vui lòng kiểm tra mã, tên hoặc vị trí ghế.');
 if(error.code==='22001')throw new Error('Một trường vượt số ký tự cho phép. Vui lòng rút ngắn nội dung.');
 if(error.code==='22003')throw new Error('Giá trị số hoặc tổng tiền vượt giới hạn dữ liệu cho phép.');
 if(error.code==='23514'||error.code==='22P02'||error.code==='23502')throw new Error('Dữ liệu không hợp lệ. Vui lòng kiểm tra các trường bắt buộc và giá trị đã nhập.');
 throw new Error(error.message);
}
