import type {Movie} from './types';

export function weeklyTickets(movie:Movie):number{
 const value=movie.weekly_tickets_sold;
 return typeof value==='number'&&Number.isFinite(value)&&value>0?Math.floor(value):0;
}

export function selectFeaturedMovie(movies:Movie[]=[]):Movie|undefined{
 const byId=(a:Movie,b:Movie)=>BigInt(a.id)<BigInt(b.id)?-1:BigInt(a.id)>BigInt(b.id)?1:0;
 const candidates=movies.filter(movie=>movie.status!=='stopped').sort((a,b)=>weeklyTickets(b)-weeklyTickets(a)||byId(a,b));
 if(candidates[0]&&weeklyTickets(candidates[0])>0)return candidates[0];
 return candidates.filter(movie=>movie.status==='showing').sort(byId)[0]||candidates.sort(byId)[0];
}
