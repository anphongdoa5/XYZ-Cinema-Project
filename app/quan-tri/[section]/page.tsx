import { notFound } from 'next/navigation';
import { AdminScreen } from '@/components/cinema/admin';
export default async function Page({params}:{params:Promise<{section:string}>}){const {section}=await params;if(!['phim','phong-chieu','lich-chieu','don-ve','khuyen-mai','bao-cao'].includes(section))notFound();return <AdminScreen section={section}/>;}

