import {notFound} from 'next/navigation';
import {AdminScreen} from '@/components/cinema/admin';
export default async function Page({params,searchParams}:{params:Promise<{section:string}>;searchParams:Promise<{edit?:string}>}){const {section}=await params;const {edit}=await searchParams;if(!['phim','phong-chieu','lich-chieu','don-ve','bao-cao','khuyen-mai'].includes(section))notFound();return <AdminScreen key={section} section={section} editor={edit}/>;}
