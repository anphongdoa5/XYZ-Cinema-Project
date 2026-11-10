import {NextRequest} from 'next/server';
import {paymentDatabase,vnpayConfig} from '@/lib/payments/vnpay';
import {verifyVnpay} from '@/lib/payments/vnpay-protocol';
export const runtime='nodejs';
export const dynamic='force-dynamic';
const reply=(RspCode:string,Message:string)=>Response.json({RspCode,Message},{headers:{'Cache-Control':'no-store'}});
export async function GET(request:NextRequest){
 try{
  if(request.url.length>8192)return reply('97','Invalid signature');
  const config=vnpayConfig();const params=verifyVnpay(request.nextUrl.searchParams,config.secret,config.merchant);
  if(!params)return reply('97','Invalid signature');
  const {data,error}=await paymentDatabase().rpc('cinema_vnpay_ipn',{p_ref:params.vnp_TxnRef,p_amount:Number(params.vnp_Amount),p_response:params.vnp_ResponseCode,p_status:params.vnp_TransactionStatus,p_transaction:params.vnp_TransactionNo||'',p_pay_date:params.vnp_PayDate||''});
  if(error||!data)return reply('99','Unable to process notification');
  return reply(data.RspCode,data.Message);
 }catch{return reply('99','Unable to process notification');}
}
