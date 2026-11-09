import { Checkout } from '@/components/cinema/orders';
export default async function Page({params}:{params:Promise<{id:string}>}){const {id}=await params;return <Checkout key={id} id={id}/>;}

