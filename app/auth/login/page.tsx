import {AuthScreen} from '@/components/cinema/auth';
import {safeNext} from '@/lib/cinema/domain';
import {redirect} from 'next/navigation';
export default async function Page({searchParams}:{searchParams:Promise<{next?:string;staff?:string}>}){const q=await searchParams;if(q.staff==='1')redirect('/admin/login');return <AuthScreen next={safeNext(q.next??null)}/>;}
