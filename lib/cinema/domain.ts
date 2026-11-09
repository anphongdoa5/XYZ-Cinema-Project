export const money = (value:number) => new Intl.NumberFormat('vi-VN',{style:'currency',currency:'VND',maximumFractionDigits:0}).format(value);
export const date = (value:string) => new Intl.DateTimeFormat('vi-VN',{timeZone:'Asia/Ho_Chi_Minh',day:'2-digit',month:'2-digit',year:'numeric'}).format(new Date(value));
export const time = (value:string) => new Intl.DateTimeFormat('vi-VN',{timeZone:'Asia/Ho_Chi_Minh',hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date(value));
export const vnDay = (value:string) => new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Ho_Chi_Minh',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(value));
export const seatPrice=(base:number,kind:string)=>Math.floor(base*(kind==='vip'?1.2:kind==='couple'?2:1));
export const seatKind=(kind:string)=>({standard:'Thường',vip:'VIP',couple:'Đôi · 2 chỗ'}[kind]||kind);
export const statusLabel=(status:string)=>({showing:'Đang chiếu',coming:'Sắp chiếu',stopped:'Ngừng',active:'Hoạt động',maintenance:'Bảo trì',open:'Mở bán',closed:'Đóng bán',available:'Trống',held:'Đang giữ',sold:'Đã bán',pending:'Chờ thanh toán',paid:'Đã thanh toán',cancelled:'Đã hủy',expired:'Hết hạn',valid:'Hợp lệ',used:'Đã dùng',success:'Thành công',failed:'Thất bại',paused:'Tạm dừng'}[status]||status);
export function safeNext(value:string|null){
 if(!value?.startsWith('/')||value.length>2048||/[\u0000-\u0020\u007f\\]/.test(value))return '/';
 try{const url=new URL(value,'https://xyz-cinema.invalid');return url.origin==='https://xyz-cinema.invalid'?url.pathname+url.search+url.hash:'/';}catch{return '/';}
}
export function discountFor(subtotal:number,kind:string,value:number,cap:number){ return Math.min(subtotal,kind==='fixed'?value:Math.min(Math.floor(subtotal*value/100),cap)); }
export function inRange(value:string|null,from:string,to:string){ if(!value||!Number.isFinite(Date.parse(value)))return false;const day=vnDay(value);return (!from||day>=from)&&(!to||day<=to); }
