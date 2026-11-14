"use client";
import {useState} from 'react';
import Link from 'next/link';
import {api,Shell,AdminFrame,Field,Button,ErrorBox,Heading} from './ui';
export function Recovery({update=false,internal=false}:{update?:boolean;internal?:boolean}){
 const [busy,setBusy]=useState(false),[error,setError]=useState(''),[done,setDone]=useState(false);
 async function submit(e:React.FormEvent<HTMLFormElement>){e.preventDefault();setBusy(true);setError('');const form=new FormData(e.currentTarget);
  try{const password=String(form.get('password'));if(password!==form.get('confirm'))throw new Error('Mật khẩu nhập lại chưa khớp.');await api('change-password',{current:String(form.get('current')),password});setDone(true);}catch(e){setError((e as Error).message);}finally{setBusy(false);}
 }
 const content=<main className="page"><div className="panel stack" style={{maxWidth:500,margin:'30px auto'}}><Heading label="TÀI KHOẢN" title={update?'Đổi mật khẩu':'Quên mật khẩu'}/>
 {!update?<p className="notice">Vui lòng liên hệ bộ phận hỗ trợ của rạp để khôi phục tài khoản. Nếu bạn vẫn đăng nhập được, hãy dùng chức năng đổi mật khẩu.</p>:done?<p className="notice success">Mật khẩu đã được cập nhật. Vui lòng đăng nhập lại.</p>:<form className="stack" onSubmit={submit}>
 <Field label="Mật khẩu hiện tại *"><input name="current" type="password" autoComplete="current-password" required/></Field>
 <Field label="Mật khẩu mới *"><input name="password" type="password" autoComplete="new-password" required minLength={8}/></Field>
 <Field label="Nhập lại mật khẩu *"><input name="confirm" type="password" autoComplete="new-password" required minLength={8}/></Field>
 {error&&<ErrorBox message={error}/>}<Button disabled={busy} size="lg">{busy?'Đang xử lý…':'Lưu mật khẩu'}</Button></form>}
 <Link className="link" href={internal?'/admin/login':'/auth/login'}>Về đăng nhập</Link></div></main>;return internal?<AdminFrame>{content}</AdminFrame>:<Shell>{content}</Shell>;
}
