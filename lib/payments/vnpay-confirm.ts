import 'server-only';
import {queryRequest,verifyQueryResponse} from './vnpay-query-protocol';
import {paymentDatabase,vnpayConfig} from './vnpay';
import type {VnpParams} from './vnpay-protocol';
export async function settleVerifiedPayment(params:VnpParams){
 const {data,error}=await paymentDatabase().rpc('cinema_vnpay_ipn',{p_ref:params.vnp_TxnRef,p_amount:Number(params.vnp_Amount),p_response:params.vnp_ResponseCode,p_status:params.vnp_TransactionStatus,p_transaction:params.vnp_TransactionNo||'',p_pay_date:params.vnp_PayDate||''});
 if(error||!data||!['00','02'].includes(data.RspCode))throw Error('Chưa cập nhật được kết quả thanh toán. Vui lòng kiểm tra lại đơn.');
 return data;
}
export async function reconcileVnpay(orderId:string,customerId:string){
 const config=vnpayConfig(),db=paymentDatabase();
 const {data:attempt,error}=await db.rpc('cinema_vnpay_query_attempt',{p_order:orderId,p_customer:customerId});
 if(error)throw Error(error.code==='PGRST202'?'Cần chạy supabase/deploy.sql để cập nhật đối soát VNPay.':'Chưa kiểm tra được giao dịch VNPay.');
 if(!attempt||attempt.throttled)return {checked:false,message:attempt?.throttled?'Hệ thống vừa kiểm tra giao dịch. Vui lòng đợi một phút trước khi kiểm tra lại.':'Không còn giao dịch VNPay cần kiểm tra.'};
 let body:unknown;
 try{const response=await fetch('https://sandbox.vnpayment.vn/merchant_webapi/api/transaction',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(queryRequest(attempt.ref,attempt.created_at,config.merchant,config.secret)),signal:AbortSignal.timeout(12000),cache:'no-store'});if(!response.ok)throw Error();body=await response.json();}catch{throw Error('Chưa kết nối được dịch vụ tra cứu VNPay. Vui lòng thử lại sau.');}
 const values=verifyQueryResponse(body,config.secret,config.merchant,attempt.ref,Number(attempt.amount));
 if(!values)throw Error('VNPay chưa trả về kết quả truy vấn có thể xác minh. Nếu đang ở trang thanh toán VNPay, hãy bấm quay lại website để nhận kết quả.');
 if(values.vnp_ResponseCode==='00'&&values.vnp_TransactionType==='01'&&values.vnp_TransactionStatus==='00'){
  await settleVerifiedPayment({...values,vnp_ResponseCode:'00'});return {checked:true,message:'Đã xác nhận kết quả từ VNPay.'};
 }
 if(values.vnp_ResponseCode==='00'&&values.vnp_TransactionType==='01'&&values.vnp_TransactionStatus==='02'){
  await settleVerifiedPayment({...values,vnp_ResponseCode:'99'});return {checked:true,message:'VNPay xác nhận giao dịch không thành công.'};
 }
 return {checked:true,message:'VNPay chưa xác nhận thanh toán thành công. Vui lòng kiểm tra lại sau.'};
}
