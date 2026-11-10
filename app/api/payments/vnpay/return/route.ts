import {NextRequest} from 'next/server';
import {paymentDatabase,vnpayConfig} from '@/lib/payments/vnpay';
import {verifyVnpay} from '@/lib/payments/vnpay-protocol';
import {reconcileVnpay,settleVerifiedPayment} from '@/lib/payments/vnpay-confirm';
export const runtime='nodejs';
export const dynamic='force-dynamic';
const redirect=(url:URL)=>new Response(null,{status:303,headers:{Location:url.href,'Cache-Control':'no-store'}});
export async function GET(request:NextRequest){
 // Sandbox localhost cannot receive provider IPN. A signed, bound callback can confirm it.
 // Public deployments use IPN or a separately authenticated server-to-server query.
 try{
  const config=vnpayConfig();const values=request.url.length<=8192?verifyVnpay(request.nextUrl.searchParams,config.secret,config.merchant):null;
  if(values){const {data,error}=await paymentDatabase().rpc('cinema_vnpay_lookup',{p_ref:values.vnp_TxnRef});
   if(!error&&data&&/^\d+$/.test(data.order_id)){
    if(['localhost','127.0.0.1','[::1]'].includes(config.app.hostname)){
     try{await settleVerifiedPayment(values);}catch{/* Keep the order accessible for a retry; never report a failed write as paid. */}
    }else if(data.customer_id){try{await reconcileVnpay(data.order_id,data.customer_id);}catch{/* IPN can still complete independently. */}}
    return redirect(new URL('/don/'+data.order_id+'/thanh-toan?vnpay=returned',config.app));
   }
  }
  return redirect(new URL('/thanh-toan/ket-qua',config.app));
 }catch{return new Response('Không xác minh được kết quả VNPay. Vui lòng mở Vé của tôi để kiểm tra đơn.',{status:503,headers:{'Content-Type':'text/plain; charset=utf-8','Cache-Control':'no-store'}});}
}
