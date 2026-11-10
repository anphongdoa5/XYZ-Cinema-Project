import 'server-only';
import {isIP} from 'node:net';
import {createClient} from '@supabase/supabase-js';
import {canonicalQuery,signVnpay,vnpayDate} from './vnpay-protocol';
const unavailable='VNPay Sandbox chưa được cấu hình. Bạn vẫn có thể thanh toán mô phỏng.';
export function vnpayConfig(){
 const merchant=process.env.VNPAY_TMN_CODE?.trim(),secret=process.env.VNPAY_HASH_SECRET?.trim(),serviceKey=process.env.SUPABASE_SECRET_KEY?.trim(),databaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
 if(!merchant||!secret||!serviceKey||!databaseUrl||!/^[A-Za-z\d]{8}$/.test(merchant)||secret.length<16||/REPLACE|YOUR_|\.\.\./i.test(serviceKey))throw Error(unavailable);
 const app=new URL(process.env.APP_URL||''),payment=new URL(process.env.VNPAY_PAYMENT_URL||'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html'),callback=new URL(process.env.VNPAY_RETURN_URL||new URL('/api/payments/vnpay/return',app).href);
 if(payment.href!=='https://sandbox.vnpayment.vn/paymentv2/vpcpay.html'||callback.origin!==app.origin||callback.pathname!=='/api/payments/vnpay/return'||callback.search||callback.hash||app.username||app.password||callback.username||callback.password)throw Error(unavailable);
 if(app.protocol!=='https:'&&!(app.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(app.hostname)))throw Error(unavailable);
 return {merchant,secret,serviceKey,databaseUrl,app,payment,callback};
}
export function paymentDatabase(){const config=vnpayConfig();return createClient(config.databaseUrl,config.serviceKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});}
export async function vnpayAvailable(){try{const db=paymentDatabase();const result=await db.rpc('cinema_vnpay_lookup',{p_ref:'configurationCheck'});return !result.error;}catch{return false;}}
export function paymentUrl(attempt:{ref:string;amount:number;created_at:string;expires_at:string},headers:Headers){
 const config=vnpayConfig();const forwarded=headers.get('x-forwarded-for')?.split(',')[0].trim()||headers.get('x-real-ip')||'';
 const params={vnp_Version:'2.1.0',vnp_Command:'pay',vnp_TmnCode:config.merchant,vnp_Locale:'vn',vnp_CurrCode:'VND',vnp_TxnRef:attempt.ref,
  vnp_OrderInfo:'Thanh toan ve XYZ Cinema '+attempt.ref,vnp_OrderType:'other',vnp_Amount:String(Number(attempt.amount)*100),vnp_ReturnUrl:config.callback.href,
  vnp_IpAddr:isIP(forwarded)?forwarded:'127.0.0.1',vnp_CreateDate:vnpayDate(attempt.created_at),vnp_ExpireDate:vnpayDate(attempt.expires_at)};
 return config.payment.href+'?'+canonicalQuery(params)+'&vnp_SecureHash='+signVnpay(params,config.secret);
}
