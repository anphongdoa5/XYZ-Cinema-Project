"use client";
import {useEffect,useRef,useState} from 'react';
import {api,Button} from './ui';
export function VnpayStatus({orderId,onRefresh}:{orderId:string;onRefresh:()=>void}){
 const [busy,setBusy]=useState(false),[message,setMessage]=useState(''),[error,setError]=useState('');
 const initial=useRef<Promise<{message:string}>|null>(null);
 useEffect(()=>{let active=true;setBusy(true);initial.current??=api<{message:string}>('vnpay-check',{orderId});initial.current.then(result=>{if(active){setMessage(result.message);onRefresh();}}).catch(e=>{if(active)setError((e as Error).message);}).finally(()=>{if(active)setBusy(false);});return()=>{active=false;};},[orderId,onRefresh]);
 async function check(){if(busy)return;setBusy(true);setError('');try{const result=await api<{message:string}>('vnpay-check',{orderId});setMessage(result.message);onRefresh();}catch(e){setError((e as Error).message);}finally{setBusy(false);}}
 return <section className="notice stack" aria-label="Xác nhận thanh toán VNPay"><p role="status">{busy?'Đang kiểm tra kết quả thanh toán VNPay…':message||'Đang chờ kết quả VNPay. Nếu bạn đã thanh toán, hãy kiểm tra lại kết quả trước khi thực hiện giao dịch khác.'}</p>{error&&<p role="alert">{error}</p>}<div><Button variant="outline" type="button" disabled={busy} onClick={check}>{busy?'Đang kiểm tra…':'Kiểm tra lại VNPay'}</Button></div></section>;
}
