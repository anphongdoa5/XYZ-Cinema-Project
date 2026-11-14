"use client";
import { useCallback,useEffect,useId,useRef,useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { statusLabel } from '@/lib/cinema/domain';
import {sessionScopeForPath} from '@/lib/cinema/session';
import {canOpenSection} from '@/lib/cinema/permissions';
import type { Profile } from '@/lib/cinema/types';
export { Button };
export async function api<T>(path:string,body?:unknown,scope?:'customer'|'admin'):Promise<T>{
 const area=scope??sessionScopeForPath(typeof window==='undefined'?'':window.location.pathname);
 let response:Response;try{response=await fetch((area==='admin'?'/api/admin/':'/api/cinema/')+path,{method:body===undefined?'GET':'POST',headers:body===undefined?{}:{'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),cache:'no-store',signal:AbortSignal.timeout(35000)});}catch{throw new Error('Chưa xác nhận được kết quả. Vui lòng kiểm tra kết nối và trạng thái đơn trước khi thử lại.');}
 const data=await response.json();if(!response.ok)throw new Error(data.error||'Không thể tải dữ liệu.');return data;
}
export function useResource<T>(path:string,interval=0,scope?:'customer'|'admin'){
 const pathname=usePathname();const area=scope??sessionScopeForPath(pathname);const resourceKey=area+':'+path;
 const [state,setState]=useState<{key:string;data:T|null;error:string;loading:boolean}>({key:resourceKey,data:null,error:'',loading:true});
 const [revision,setRevision]=useState(0);const reload=useCallback(()=>setRevision(value=>value+1),[]);
 useEffect(()=>{let active=true;let running=false;setState(current=>current.key===resourceKey?current:{key:resourceKey,data:null,error:'',loading:true});
  const load=async()=>{if(running)return;running=true;try{const data=await api<T>(path,undefined,area);if(active)setState({key:resourceKey,data,error:'',loading:false});}
   catch(error){if(active)setState(current=>({key:resourceKey,data:current.key===resourceKey?current.data:null,error:(error as Error).message,loading:false}));}finally{running=false;}};
  void load();const timer=interval?setInterval(load,interval):undefined;return()=>{active=false;clearInterval(timer);};
 },[path,interval,revision,area,resourceKey]);
 const current=state.key===resourceKey?state:{key:resourceKey,data:null,error:'',loading:true};return {data:current.data,error:current.error,loading:current.loading,reload};
}
export function Brand({href='/'}:{href?:string}){return <Link href={href} className="brand"><span className="brand-mark">X</span>XYZ Cinema</Link>;}
export const adminLinks=[['phim','Phim'],['phong-chieu','Phòng chiếu và ghế'],['lich-chieu','Lịch chiếu'],['don-ve','Đơn và vé'],['khuyen-mai','Khuyến mãi'],['bao-cao','Báo cáo'],['tai-khoan','Tài khoản nội bộ'],['nhat-ky','Nhật ký hoạt động'],['van-hanh','Vận hành theo suất'],['kiem-soat','Kiểm soát vé'],['mat-khau','Đổi mật khẩu']];
export function AdminFrame({children}:{children:React.ReactNode}){const path=usePathname(),me=useResource<{profile:Profile|null}>('me',0,'admin');return <Shell admin><div className="admin-shell"><aside className="sidebar" aria-label="Quản trị">{adminLinks.filter(([key])=>me.data?.profile&&canOpenSection(me.data.profile.role,key)).map(([key,label])=><Link href={'/admin/'+key} className={path.includes('/'+key)?'active':''} key={key}>{label}</Link>)}</aside><main className="admin-content stack">{children}</main></div></Shell>;}
export function Shell({children,admin:requestedAdmin=false}:{children:React.ReactNode;admin?:boolean}){
 const path=usePathname();const admin=requestedAdmin||sessionScopeForPath(path)==='admin';const me=useResource<{profile:Profile|null}>('me',0,admin?'admin':'customer');const [logoutError,setLogoutError]=useState('');
 async function logout(){try{await api('logout',{},admin?'admin':'customer');window.location.assign(admin?'/admin/login':'/');}catch(e){setLogoutError((e as Error).message);}}
 return <div className={'cinema-app '+(admin?'admin-app':'customer-app')}><header className="header"><Brand href={admin?'/admin':'/'}/>{!admin&&<nav className="nav" aria-label="Điều hướng chính"><Link className={path==='/'?'active':''} href="/">Trang chủ</Link><Link className={path.includes('don-ve')?'active':''} href="/tai-khoan/don-ve">Vé của tôi</Link></nav>}<div className="account">{me.data?.profile?<><span className="badge">{admin?(me.data.profile.role==='admin'?'Quản trị viên':'Nhân viên rạp'):'Khách hàng'} / {me.data.profile.full_name||me.data.profile.email}</span><button onClick={logout} className={admin?'accent':'muted'}>Đăng xuất</button></>:admin?<Link className="accent" href="/admin/login">Đăng nhập nội bộ</Link>:<span className="badge guest-account">Khách / <Link href="/auth/login">Đăng nhập</Link> · <Link href="/auth/sign-up">Đăng ký</Link></span>}</div></header>{logoutError&&<div className="page"><ErrorBox message={logoutError}/></div>}{children}<footer className="footer"><span>XYZ Cinema / {admin?'Không gian nội bộ':'Trải nghiệm vượt xa điện ảnh'}</span></footer></div>;
}
export function Heading({label,title,description,action}:{label:string;title:string;description?:string;action?:React.ReactNode}){return <div className="row between"><div><p className="eyebrow">{label}</p><h1>{title}</h1>{description&&<p className="muted mt-2">{description}</p>}</div>{action}</div>;}
export function Field({label,children,hint,error,className=''}:{label:string;children:React.ReactNode;hint?:string;error?:string;className?:string}){return <div className={'field '+className}><label className="field-label"><span>{label}</span>{children}</label>{error?<small className="field-error" role="alert">{error}</small>:hint?<small>{hint}</small>:null}</div>;}
export function Badge({status}:{status:string}){return <span className={'badge '+status}>{statusLabel(status)}</span>;}
export function KV({label,children}:{label:string;children:React.ReactNode}){return <div className="kv"><span>{label}</span><strong>{children}</strong></div>;}
export function ErrorBox({message,retry}:{message:string;retry?:()=>void}){const path=usePathname();const login=(sessionScopeForPath(path)==='admin'?"/admin/login":"/auth/login")+"?next="+encodeURIComponent(path);return <div className="notice error" role="alert"><p>{message}</p>{message.includes('đăng nhập')&&<Button asChild variant="outline" className="mt-3"><Link href={login}>Đăng nhập lại</Link></Button>}{retry&&<Button variant="outline" className="mt-3" onClick={retry}>Thử lại</Button>}</div>;}
export function Loading(){return <div className="stack" role="status" aria-label="Đang tải"><div className="skeleton"/><p className="muted">Đang tải dữ liệu…</p></div>;}
export function Empty({title='Chưa có dữ liệu',description,children}:{title?:string;description?:string;children?:React.ReactNode}){return <div className="empty panel"><h2>{title}</h2>{description&&<p className="muted">{description}</p>}{children}</div>;}
export function Poster({src,title,className=''}:{src?:string;title:string;className?:string}){const [bad,setBad]=useState(false);return src&&!bad?<img className={'poster '+className} src={src} alt={'Poster '+title} onError={()=>setBad(true)}/>:<div className={'poster '+className} role="img" aria-label={'Chưa có poster: '+title}/>;}
export function Steps({step}:{step:number}){return <nav className="steps" aria-label="Tiến trình đặt vé">{['Suất chiếu','Chọn ghế','Xác nhận','Thanh toán','Nhận vé'].map((x,i)=><span key={x} className={'step '+(i===step?'active':i<step?'complete':'')} aria-current={i===step?'step':undefined}><i>{i<step?'✓':i+1}</i>{x}</span>)}</nav>;}
export function Modal({open,title,label,children,actions,onClose,danger=false,busy=false}:{open:boolean;title:string;label:string;children:React.ReactNode;actions:React.ReactNode;onClose:()=>void;danger?:boolean;busy?:boolean}){
 const dialog=useRef<HTMLDialogElement>(null);const titleId=useId();
 useEffect(()=>{const el=dialog.current;const previous=document.activeElement as HTMLElement|null;if(open&&!el?.open)el?.showModal();if(!open&&el?.open)el.close();return()=>{if(el?.open)el.close();previous?.focus();};},[open]);
 return <dialog ref={dialog} className="modal" aria-labelledby={titleId} onCancel={e=>{e.preventDefault();if(!busy)onClose();}}><div className="modal-body"><p className={'eyebrow '+(danger?'danger':'')}>{label}</p><h2 id={titleId}>{title}</h2>{children}<div className="modal-actions">{actions}</div></div></dialog>;
}
export function Timer({expires,serverNow,label,onExpire,hint}:{expires:string;serverNow:string;label:string;onExpire?:()=>void;hint?:string}){
 const [remaining,setRemaining]=useState<number|null>(null);const expired=useRef<string|null>(null);const callback=useRef(onExpire);
 useEffect(()=>{callback.current=onExpire;},[onExpire]);
 useEffect(()=>{const anchor=performance.now();const initial=Date.parse(expires)-Date.parse(serverNow);const tick=()=>{const ms=Math.max(0,initial-(performance.now()-anchor));setRemaining(Math.ceil(ms/1000));if(ms===0&&expired.current!==expires){expired.current=expires;callback.current?.();}};tick();const timer=setInterval(tick,1000);return()=>clearInterval(timer);},[expires,serverNow]);
 return <div className="timer"><span><b>{label}</b>{hint&&<small>{hint}</small>}</span><strong>{remaining===null?'--:--':`${Math.floor(remaining/60).toString().padStart(2,'0')}:${(remaining%60).toString().padStart(2,'0')}`}</strong></div>;
}
