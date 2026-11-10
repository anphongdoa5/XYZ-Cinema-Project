import {createHmac,timingSafeEqual} from 'node:crypto';
import {randomUUID} from 'node:crypto';
import {vnpayDate,type VnpParams} from './vnpay-protocol';
const requestFields=['vnp_RequestId','vnp_Version','vnp_Command','vnp_TmnCode','vnp_TxnRef','vnp_TransactionDate','vnp_CreateDate','vnp_IpAddr','vnp_OrderInfo'];
const responseFields=['vnp_ResponseId','vnp_Command','vnp_ResponseCode','vnp_Message','vnp_TmnCode','vnp_TxnRef','vnp_Amount','vnp_BankCode','vnp_PayDate','vnp_TransactionNo','vnp_TransactionType','vnp_TransactionStatus','vnp_OrderInfo'];
const digest=(values:VnpParams,fields:string[],secret:string)=>createHmac('sha512',secret).update(fields.map(field=>values[field]??'').join('|'),'utf8').digest('hex');
export function queryRequest(ref:string,createdAt:string,merchant:string,secret:string,ip='127.0.0.1',now=new Date()){
 const values:VnpParams={vnp_RequestId:randomUUID().replaceAll('-',''),vnp_Version:'2.1.0',vnp_Command:'querydr',vnp_TmnCode:merchant,vnp_TxnRef:ref,vnp_TransactionDate:vnpayDate(createdAt),vnp_CreateDate:vnpayDate(now.toISOString()),vnp_IpAddr:ip,vnp_OrderInfo:'Kiem tra thanh toan ve XYZ Cinema '+ref};
 return {...values,vnp_TransactionNo:'',vnp_SecureHash:digest(values,requestFields,secret)};
}
export function verifyQueryResponse(input:unknown,secret:string,merchant:string,ref:string,amount:number):VnpParams|null{
 if(!input||typeof input!=='object'||Array.isArray(input))return null;
 const values:VnpParams={};for(const [key,value] of Object.entries(input)){if(typeof value!=='string'&&typeof value!=='number')return null;values[key]=String(value);if(values[key].length>1024)return null;}
 const hash=values.vnp_SecureHash;
 if(!hash||!/^[a-f\d]{128}$/i.test(hash)||values.vnp_TmnCode!==merchant||values.vnp_TxnRef!==ref||(values.vnp_Command&&values.vnp_Command!=='querydr')||!/^\d{1,12}$/.test(values.vnp_Amount||'')||Number(values.vnp_Amount)!==amount*100)return null;
 const fields=[...responseFields,'vnp_PromotionCode','vnp_PromotionAmount'];
 let valid=timingSafeEqual(Buffer.from(hash,'hex'),Buffer.from(digest(values,fields,secret),'hex'));
 // VNPay's original 2.1.0 response has no promotion fields; never drop fields that are present.
 if(!valid&&!Object.hasOwn(values,'vnp_PromotionCode')&&!Object.hasOwn(values,'vnp_PromotionAmount'))valid=timingSafeEqual(Buffer.from(hash,'hex'),Buffer.from(digest(values,responseFields,secret),'hex'));
 if(!valid)return null;
 return values;
}
