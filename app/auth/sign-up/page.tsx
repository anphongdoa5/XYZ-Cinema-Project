import { AuthScreen } from '@/components/cinema/auth';
import { safeNext } from '@/lib/cinema/domain';
export default async function Page({searchParams}:{searchParams:Promise<{next?:string;staff?:string}>}){const query=await searchParams;return <AuthScreen signup={true} staff={query.staff==='1'} next={safeNext(query.next||null)}/>;}
