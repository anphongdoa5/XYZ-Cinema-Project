import type {AdminData,Order} from './types';
import {inRange,vnDay} from './domain';

export type ReportFilters={from:string;to:string;movie:string;room:string;promotion:string};
export const emptyReportFilters:ReportFilters={from:'',to:'',movie:'',room:'',promotion:''};
const sum=(orders:Order[],field:'subtotal'|'discount'|'total')=>orders.reduce((value,o)=>value+o[field],0);
const countTickets=(orders:Order[])=>orders.reduce((value,o)=>value+o.tickets.filter(t=>t.status!=='cancelled').length,0);

/** Chương 4.3: dates are Vietnamese calendar days; refunds use their own date. */
export function buildReports(data:AdminData,filters:ReportFilters){
 const shows=new Map(data.showtimes.map(s=>[s.id,s]));
 const seats=new Map(data.seats.map(s=>[s.id,s]));
 const rooms=new Map(data.rooms.map(r=>[r.id,r]));
 const movies=new Map(data.movies.map(m=>[m.id,m]));
 const movieOrders=data.orders.filter(o=>!filters.movie||shows.get(o.showtime_id)?.movie_id===filters.movie);
 const paidAt=(o:Order)=>o.transactions.find(t=>t.kind==='payment'&&t.result==='success')?.created_at??o.paid_at;
 const charged=movieOrders.filter(o=>(o.status==='paid'||o.status==='cancelled')&&inRange(paidAt(o),filters.from,filters.to));
 const paid=charged.filter(o=>o.status==='paid');
 const revenueDays=new Map<string,Order[]>();
 for(const order of paid){const day=vnDay(paidAt(order)!);const list=revenueDays.get(day)??[];list.push(order);revenueDays.set(day,list);}
 const days=[...revenueDays].sort(([a],[b])=>a.localeCompare(b)).map(([day,orders])=>({day,orders:orders.length,tickets:countTickets(orders),subtotal:sum(orders,'subtotal'),discount:sum(orders,'discount'),revenue:sum(orders,'total')}));
 const flowDays=new Map<string,{day:string;receipts:number;refunds:number;net:number}>();
 for(const order of movieOrders)for(const transaction of order.transactions){
  if(transaction.result!=='success'||!inRange(transaction.created_at,filters.from,filters.to))continue;
  const day=vnDay(transaction.created_at);const row=flowDays.get(day)??{day,receipts:0,refunds:0,net:0};
  if(transaction.kind==='payment')row.receipts+=transaction.amount;
  if(transaction.kind==='refund')row.refunds+=transaction.amount;
  row.net=row.receipts-row.refunds;flowDays.set(day,row);
 }
 const flows=[...flowDays.values()].sort((a,b)=>a.day.localeCompare(b.day));
 const revenue={orders:paid.length,tickets:countTickets(paid),subtotal:sum(paid,'subtotal'),discount:sum(paid,'discount'),revenue:sum(paid,'total'),average:paid.length?sum(paid,'total')/paid.length:null,days,flows,
  receipts:flows.reduce((n,r)=>n+r.receipts,0),refunds:flows.reduce((n,r)=>n+r.refunds,0)};

 const inventory=new Map<string,AdminData['inventory']>();
 for(const item of data.inventory){const list=inventory.get(item.showtime_id)??[];list.push(item);inventory.set(item.showtime_id,list);}
 const cancelledByShow=new Map<string,number>();
 for(const order of data.orders)cancelledByShow.set(order.showtime_id,(cancelledByShow.get(order.showtime_id)??0)+order.tickets.filter(t=>t.status==='cancelled').length);
 const occupancyRows=data.showtimes.filter(s=>s.status!=='stopped'&&inRange(s.starts_at,filters.from,filters.to)&&(!filters.movie||s.movie_id===filters.movie)&&(!filters.room||s.room_id===filters.room)).map(show=>{
  const rows=inventory.get(show.id)??[];const places=(id:string)=>seats.get(id)?.kind==='couple'?2:1;
  const blocked=rows.filter(x=>x.status==='blocked');const sellable=rows.filter(x=>x.status!=='blocked');
  const sold=rows.filter(x=>x.status==='sold');const held=rows.filter(x=>x.status==='held'&&Date.parse(x.expires_at??'')>Date.parse(data.server_now));
  const capacity=sellable.reduce((n,x)=>n+places(x.seat_id),0);const soldPlaces=sold.reduce((n,x)=>n+places(x.seat_id),0);
  return {show,movie:movies.get(show.movie_id)?.title??'Phim',room:rooms.get(show.room_id)?.name??'Phòng',units:rows.length,places:rows.reduce((n,x)=>n+places(x.seat_id),0),capacity,
   sold:sold.length,held:held.length,blocked:blocked.length,available:rows.length-sold.length-held.length-blocked.length,cancelled:cancelledByShow.get(show.id)??0,soldPlaces,percent:capacity?soldPlaces/capacity*100:null};
 });
 const byRoom=new Map<string,{id:string;name:string;capacity:number;soldPlaces:number;percent:number|null}>();
 for(const row of occupancyRows){const room=byRoom.get(row.show.room_id)??{id:row.show.room_id,name:row.room,capacity:0,soldPlaces:0,percent:null};room.capacity+=row.capacity;room.soldPlaces+=row.soldPlaces;room.percent=room.capacity?room.soldPlaces/room.capacity*100:null;byRoom.set(room.id,room);}
 const capacity=occupancyRows.reduce((n,r)=>n+r.capacity,0),soldPlaces=occupancyRows.reduce((n,r)=>n+r.soldPlaces,0);
 const occupancy={rows:occupancyRows,byRoom:[...byRoom.values()],shows:occupancyRows.length,tickets:occupancyRows.reduce((n,r)=>n+r.sold,0),soldPlaces,capacity,percent:capacity?soldPlaces/capacity*100:null};

 const promotionOrders=charged.filter(o=>o.promotion_id&&(!filters.promotion||o.promotion_id===filters.promotion));
 const activePromotionOrders=promotionOrders.filter(o=>o.status==='paid');
 const programs=data.promotions.filter(p=>(!filters.promotion||p.id===filters.promotion)&&promotionOrders.some(o=>o.promotion_id===p.id)).map(p=>{
  const list=promotionOrders.filter(o=>o.promotion_id===p.id);const active=list.filter(o=>o.status==='paid');
  return {program:p,orders:list.length,cancelled:list.filter(o=>o.status==='cancelled').length,discount:sum(active,'discount'),revenue:sum(active,'total'),average:active.length?sum(active,'total')/active.length:null};
 });
 const promotions={rows:programs,programs:new Set(promotionOrders.map(o=>o.promotion_id)).size,orders:promotionOrders.length,discount:sum(activePromotionOrders,'discount'),revenue:sum(activePromotionOrders,'total')};
 return {revenue,occupancy,promotions};
}
