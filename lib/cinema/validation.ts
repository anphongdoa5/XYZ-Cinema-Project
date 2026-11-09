import {z} from 'zod';
export const cinemaId=z.string().regex(/^[1-9]\d{0,18}$/).refine(value=>BigInt(value)<=BigInt('9223372036854775807'));
const optionalText=(max:number)=>z.string().max(max).optional().default('');
const money=z.number().int().min(0).max(99999999);
const identity={id:cinemaId.optional()};
const movie=z.object({...identity,title:z.string().trim().min(1).max(255),duration:z.number().int().min(1).max(600),
 genres:z.string().trim().min(1).max(1500).refine(value=>value.split(',').every(genre=>genre.trim().length>0&&genre.trim().length<=100)),
 age:z.enum(['P','C13','C16','C18']),language:z.string().trim().min(1).max(50),description:optionalText(20000),director:optionalText(100),actors:optionalText(5000),country:optionalText(100),
 poster_url:optionalText(255).refine(value=>!value||isHttpsUrl(value)),trailer_url:optionalText(2048).refine(value=>!value||isYoutubeUrl(value)),
 release_date:z.union([z.literal(''),z.iso.date()]).optional().default(''),status:z.enum(['showing','coming','stopped'])});
const seat=z.object({row_no:z.number().int().min(1).max(20),col_no:z.number().int().min(1).max(30),kind:z.enum(['standard','vip','couple']),label:z.string().optional()});
const room=z.object({...identity,name:z.string().trim().min(1).max(50),status:z.enum(['active','maintenance']),seats:z.array(seat).min(1).max(600).optional()});
const show=z.object({...identity,movie_id:cinemaId,room_id:cinemaId,starts_at:z.iso.datetime({offset:true}),base_price:z.number().int().min(1).max(10000000),format:z.string().trim().min(1).max(71).refine(value=>{const [format,...language]=value.split(' ');return format.length<=20&&language.join(' ').length<=50;})});
const promotion=z.object({...identity,code:z.string().trim().min(1).max(50),name:z.string().trim().min(1).max(100),kind:z.enum(['percent','fixed']),value:money.refine(value=>value>0),
 max_discount:money.nullable(),min_order:money,starts_at:z.iso.datetime({offset:true}),ends_at:z.iso.datetime({offset:true}),max_uses:z.number().int().min(1).max(2147483647).nullable(),status:z.enum(['active','paused','stopped'])})
 .refine(value=>value.kind!=='percent'||value.value<=100,{path:['value']}).refine(value=>Date.parse(value.ends_at)>=Date.parse(value.starts_at),{path:['ends_at']});
export type AdminEntity='movies'|'rooms'|'showtimes'|'promotions';
export function parseAdminData(entity:AdminEntity,input:unknown):Record<string,unknown>{
 const result=({movies:movie,rooms:room,showtimes:show,promotions:promotion}[entity]).safeParse(input);
 if(result.success)return result.data;
 const labels:Record<string,string>={title:'Tên phim',duration:'Thời lượng',genres:'Thể loại',age:'Phân loại tuổi',language:'Ngôn ngữ',poster_url:'Poster HTTPS (tối đa 255 ký tự)',trailer_url:'Trailer YouTube',release_date:'Ngày khởi chiếu',name:'Tên',starts_at:'Thời gian bắt đầu',ends_at:'Thời gian kết thúc',base_price:'Giá cơ bản',format:'Định dạng',seats:'Sơ đồ ghế',value:'Giá trị giảm',max_uses:'Số lượt tối đa',max_discount:'Mức giảm tối đa',code:'Mã khuyến mãi',min_order:'Đơn tối thiểu'};
 const key=String(result.error.issues[0]?.path[0]??'');throw new Error('Vui lòng kiểm tra trường '+(labels[key]??key??'thông tin')+'. Giá trị chưa đúng định dạng hoặc vượt giới hạn.');
}
function isHttpsUrl(value:string){try{return new URL(value).protocol==='https:';}catch{return false;}}
function isYoutubeUrl(value:string){try{const url=new URL(value);return url.protocol==='https:'&&((['youtube.com','www.youtube.com'].includes(url.hostname)&&/^[\w-]{11}$/.test(url.searchParams.get('v')??''))||(url.hostname==='youtu.be'&&/^\/[\w-]{11}$/.test(url.pathname)));}catch{return false;}}
