import { OrderDetail } from '@/components/cinema/orders';
export default async function Page({params}:{params:Promise<{id:string}>}){const {id}=await params;return <OrderDetail ticketsOnly key={id} id={id}/>;}

