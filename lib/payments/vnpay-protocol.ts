import {createHmac,timingSafeEqual} from 'node:crypto';
export type VnpParams=Record<string,string>;
const encode=(value:string)=>encodeURIComponent(value).replace(/%20/g,'+');
export function canonicalQuery(params:VnpParams){
 return Object.keys(params).filter(key=>key!=='vnp_SecureHash'&&key!=='vnp_SecureHashType').sort().map(key=>encode(key)+'='+encode(params[key])).join('&');
}
export function signVnpay(params:VnpParams,secret:string){return createHmac('sha512',secret).update(canonicalQuery(params),'utf8').digest('hex');}
export function verifyVnpay(search:URLSearchParams,secret:string,merchant:string):VnpParams|null{
 const values:VnpParams={};
 for(const [key,value] of search){
  if(!/^vnp_[A-Za-z]+$/.test(key)||Object.hasOwn(values,key)||value.length>1024)return null;
  values[key]=value;
 }
 const hash=values.vnp_SecureHash;
 if(!hash||! /^[a-f\d]{128}$/i.test(hash)||values.vnp_TmnCode!==merchant)return null;
 if(!timingSafeEqual(Buffer.from(hash,'hex'),Buffer.from(signVnpay(values,secret),'hex')))return null;
 if(!/^[A-Za-z\d]{1,40}$/.test(values.vnp_TxnRef||'')||!/^\d{1,12}$/.test(values.vnp_Amount||'')||!/^\d{2}$/.test(values.vnp_ResponseCode||'')||!/^\d{2}$/.test(values.vnp_TransactionStatus||''))return null;
 return values;
}
export function vnpayDate(value:string){
 const date=new Date(value);if(!Number.isFinite(date.getTime()))throw Error('Ngày thanh toán không hợp lệ.');
 return new Date(date.getTime()+7*3600000).toISOString().slice(0,19).replace(/[-T:]/g,'');
}
