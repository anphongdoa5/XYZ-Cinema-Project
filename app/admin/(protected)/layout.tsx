import {redirect} from 'next/navigation';
import {identity} from '@/lib/cinema/server';
export const dynamic='force-dynamic';
export default async function Layout({children}:{children:React.ReactNode}){const {profile}=await identity(undefined,'admin');if(!profile?.active)redirect('/admin/login');return children;}
