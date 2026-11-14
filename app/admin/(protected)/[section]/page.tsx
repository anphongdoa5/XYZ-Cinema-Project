import {notFound,redirect} from 'next/navigation';
import {AdminScreen} from '@/components/cinema/admin';
import {InternalScreen} from '@/components/cinema/internal';
import {identity} from '@/lib/cinema/server';
import {administratorSections,employeeSections,canOpenSection} from '@/lib/cinema/permissions';
export default async function Page({params,searchParams}:{params:Promise<{section:string}>;searchParams:Promise<{edit?:string}>}){
 const {section}=await params;const {edit}=await searchParams;
 if(![...administratorSections,...employeeSections].includes(section))notFound();
 const {profile}=await identity(undefined,'admin');if(!profile)redirect('/admin/login');
 if(!canOpenSection(profile.role,section))redirect('/khong-co-quyen');
 if(['van-hanh','kiem-soat','tai-khoan','nhat-ky','don-ve'].includes(section))return <InternalScreen key={section} section={section}/>;
 return <AdminScreen key={section} section={section} editor={edit}/>;
}
