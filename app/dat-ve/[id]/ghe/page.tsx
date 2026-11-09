import { SeatSelection } from '@/components/cinema/booking';
export default async function Page({params}:{params:Promise<{id:string}>}){const {id}=await params;return <SeatSelection key={id} id={id}/>;}

