import { MovieDetail } from '@/components/cinema/catalog';
export default async function Page({params}:{params:Promise<{id:string}>}){const {id}=await params;return <MovieDetail key={id} id={id}/>;}

