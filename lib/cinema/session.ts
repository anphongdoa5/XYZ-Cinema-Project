export type SessionScope='customer'|'admin';
export const sessionCookie=(scope:SessionScope)=>scope==='admin'?'xyz_cinema_admin_session':'xyz_cinema_session';
export const sessionScopeForPath=(path:string):SessionScope=>/^\/admin(?:\/|$)/.test(path)?'admin':'customer';
export function adminNext(value:string|null|undefined){
 if(!value||!/^\/admin(?:\/|\?|$)/.test(value)||value.startsWith('/admin/login')||/[\\\s]/.test(value))return '/admin/lich-chieu';
 try{const url=new URL(value,'https://xyz.invalid');return url.origin==='https://xyz.invalid'?url.pathname+url.search:'/admin/lich-chieu';}catch{return '/admin/lich-chieu';}
}
