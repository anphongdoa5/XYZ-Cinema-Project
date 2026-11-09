import {AuthScreen} from '@/components/cinema/auth';
import {adminNext} from '@/lib/cinema/session';
export default async function Page({searchParams}:{searchParams:Promise<{next?:string}>}){const {next}=await searchParams;return <AuthScreen staff next={adminNext(next)}/>;}
