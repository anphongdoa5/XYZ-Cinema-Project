import {redirect} from 'next/navigation';
import {identity} from '@/lib/cinema/server';
import {internalHome} from '@/lib/cinema/permissions';
export default async function Page(){const {profile}=await identity(undefined,'admin');redirect(profile?internalHome(profile.role):'/admin/login');}
