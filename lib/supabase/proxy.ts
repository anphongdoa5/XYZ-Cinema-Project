import {NextResponse,type NextRequest} from 'next/server';
import {sessionCookie} from '@/lib/cinema/session';
export async function updateSession(request:NextRequest){
 const path=request.nextUrl.pathname;
 if(/^\/quan-tri(?:\/|$)/.test(path)){const url=request.nextUrl.clone();url.pathname=path.replace('/quan-tri','/admin');return NextResponse.redirect(url);}
 if(path==='/auth/login'&&request.nextUrl.searchParams.get('staff')==='1'){const url=request.nextUrl.clone();url.pathname='/admin/login';url.searchParams.delete('staff');const next=url.searchParams.get('next');if(next?.startsWith('/quan-tri'))url.searchParams.set('next',next.replace('/quan-tri','/admin'));return NextResponse.redirect(url);}
 const admin=/^\/admin(?:\/|$)/.test(path)&&path!=='/admin/login';
 const customer=/^\/(dat-ve|giu-ghe|don|tai-khoan)(?:\/|$)/.test(path);
 if((admin||customer)&&!request.cookies.get(sessionCookie(admin?'admin':'customer'))?.value){const url=request.nextUrl.clone();url.pathname=admin?'/admin/login':'/auth/login';url.search='';url.searchParams.set('next',path+request.nextUrl.search);return NextResponse.redirect(url);}
 return NextResponse.next({request});
}
