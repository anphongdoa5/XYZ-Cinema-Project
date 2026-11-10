import 'server-only';
import { NextRequest } from 'next/server';
import { cookies } from 'next/headers';
import { createClient } from '@/lib/supabase/server';
import { identity,databaseError } from '@/lib/cinema/server';
import { z } from 'zod';
import {cinemaId,parseAdminData} from '@/lib/cinema/validation';
import {sessionCookie,type SessionScope} from './session';
import {paymentDatabase,paymentUrl,vnpayAvailable,vnpayConfig} from '@/lib/payments/vnpay';
import {reconcileVnpay} from '@/lib/payments/vnpay-confirm';
const id=cinemaId;
const holdId=z.string().uuid();
const password=z.string().min(8).refine(v=>new TextEncoder().encode(v).length<=72,'Mật khẩu tối đa 72 byte UTF-8.');
const reply=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'no-store'}});
export function createCinemaHandler(scope:SessionScope){const cookieName=sessionCookie(scope);return async function handle(request:NextRequest,{params}:{params:Promise<{path:string[]}>}){
 try{
  const {path}=await params;const [resource,key]=path;
  const db=await createClient(scope);
  async function rpc(name:string,args:Record<string,unknown>={}){const r=await db.rpc(name,args);databaseError(r.error);return r.data;}
  if(request.method==='POST'&&request.headers.get('origin')!==new URL(request.url).origin)return reply({error:'Nguồn yêu cầu không hợp lệ.'},403);
  if(request.method==='GET'&&resource==='catalog')return reply(await rpc('cinema_catalog'));
  if(request.method==='GET'&&resource==='seatmap')return reply(await rpc('cinema_seatmap',{p_show:id.parse(key)}));
  if(request.method==='POST'&&['register','login','logout'].includes(resource)){
   const store=await cookies();
   if(resource==='logout'){try{await rpc('cinema_logout');}catch{/* Local logout still clears the cookie if the database is temporarily unavailable. */}finally{store.set(cookieName,'',{httpOnly:true,sameSite:'lax',secure:process.env.NODE_ENV==='production',path:'/',maxAge:0});}return reply({ok:true});}
   const body=await request.json();
   if(resource==='register'&&scope==='admin')return reply({error:'Tài khoản nhân viên được cấp riêng.'},403);
   if(resource==='login'&&scope==='customer'&&body.staff===true)return reply({error:'Vui lòng đăng nhập nhân viên tại /admin/login.'},400);
   const result=resource==='register'?await rpc('cinema_register',{
    p_name:z.string().trim().min(1).max(100).parse(body.full_name),p_email:z.email().max(100).parse(body.email),
    p_phone:z.string().regex(/^\+?[0-9]{9,15}$/).max(15).parse(body.phone),p_password:password.parse(body.password),
   }):await rpc('cinema_login',{p_login:z.string().trim().min(1).max(100).parse(body.email),p_password:z.string().max(100).parse(body.password),p_staff:scope==='admin'});
   if(result?.error)return reply({error:result.error},401);
   if(!result?.token)throw new Error('Chưa tạo được phiên đăng nhập.');
   store.set(cookieName,result.token,{httpOnly:true,sameSite:'lax',secure:process.env.NODE_ENV==='production',path:'/',maxAge:7*24*60*60});
   return reply({ok:true});
  }
  const {profile}=await identity(db,scope);
  if(request.method==='GET'&&resource==='me')return reply({profile});
  if(!profile?.active)return reply({error:'Vui lòng đăng nhập để tiếp tục.'},401);
  if(scope==='customer'&&request.method==='GET'&&resource==='payment-methods')return reply({vnpay:await vnpayAvailable()});
  if(scope==='customer'&&request.method==='POST'&&resource==='vnpay-check'){
   const body=await request.json();const orderId=id.parse(body.orderId);
   // Check ownership with the normal session before using service-only gateway RPCs.
   const own=await rpc('cinema_orders',{p_order:orderId});
   if(!own.orders?.length)return reply({error:'Không tìm thấy đơn.'},404);
   if(own.orders[0].status==='paid')return reply({checked:true,message:'Đơn đã thanh toán.'});
   return reply(await reconcileVnpay(orderId,profile.id));
  }
  if(scope==='customer'&&request.method==='POST'&&resource==='vnpay'){
   vnpayConfig();
   const body=await request.json();const {data,error}=await paymentDatabase().rpc('cinema_vnpay_begin',{p_order:id.parse(body.orderId),p_customer:id.parse(profile.id),p_expected:z.number().int().nonnegative().parse(body.expected)});
   if(error?.code==='PGRST202')return reply({error:'Chạy supabase/enable-vnpay.sql để bật VNPay Sandbox. Thanh toán mô phỏng vẫn sử dụng được.'},503);
   databaseError(error);
   if(data?.price_changed||data?.paid)return reply(data);
   if(!data?.ref)throw Error('Chưa tạo được giao dịch VNPay.');
   return reply({redirect:paymentUrl(data,request.headers)});
  }
  if(scope==='admin'&&['hold','release','order','promo','pay','reservation','holds'].includes(resource))return reply({error:'Chức năng này dành cho tài khoản khách hàng.'},403);
  if(request.method==='GET'){
   if(resource==='reservation')return reply(await rpc('cinema_reservation',{p_show:id.parse(key)}));
   if(resource==='holds')return reply(await rpc('cinema_hold_details',{p_hold:holdId.parse(key)}));
   if(resource==='orders')return reply(await rpc('cinema_orders',{p_order:key?id.parse(key):null}));
   if(resource==='admin'){if(profile.role!=='staff')return reply({error:'Bạn không có quyền quản trị.'},403);return reply(await rpc('cinema_admin'));}
   return reply({error:'Không tìm thấy chức năng.'},404);
  }
  if(request.method!=='POST')return reply({error:'Không tìm thấy chức năng.'},404);
  const body=await request.json();let name='';let args:Record<string,unknown>={};
  switch(resource){
   case 'hold':name='cinema_hold';args={p_show:id.parse(body.showtimeId),p_seats:z.array(id).min(1).max(8).parse(body.seatIds)};break;
   case 'release':name='cinema_release';args={p_hold:holdId.parse(body.holdId)};break;
   case 'order':name='cinema_order';args={p_hold:holdId.parse(body.holdId),p_expected:z.number().int().nonnegative().parse(body.expected)};break;
   case 'promo':name='cinema_promo';args={p_order:id.parse(body.orderId),p_code:z.string().max(50).parse(body.code)};break;
   case 'pay':name='cinema_pay';args={p_order:id.parse(body.orderId),p_expected:z.number().int().nonnegative().parse(body.expected)};break;
   case 'cancel':name='cinema_cancel';args={p_order:id.parse(body.orderId)};break;
   case 'change-password':name='cinema_change_password';args={p_current:z.string().max(100).parse(body.current),p_new:password.parse(body.password)};break;
   case 'stop-show':if(profile.role!=='staff')return reply({error:'Không có quyền.'},403);name='cinema_stop_show';args={p_show:id.parse(body.showtimeId),p_expected:body.expected||null};break;
   case 'save':{if(profile.role!=='staff')return reply({error:'Không có quyền.'},403);const entity=z.enum(['movies','rooms','showtimes','promotions']).parse(body.entity);name='cinema_admin_save';args={p_entity:entity,p_data:parseAdminData(entity,body.data)};break;}
   default:return reply({error:'Không tìm thấy chức năng.'},404);
  }
  const data=await rpc(name,args);
  if(resource==='change-password')(await cookies()).set(cookieName,'',{httpOnly:true,sameSite:'lax',secure:process.env.NODE_ENV==='production',path:'/',maxAge:0});
  return reply(data??{ok:true});
 }catch(error){return reply({error:error instanceof z.ZodError?'Dữ liệu gửi lên không hợp lệ.':error instanceof Error?error.message:'Không thể hoàn tất thao tác.'},400);}
}
}
