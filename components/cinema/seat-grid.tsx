"use client";
import {useRef,useState} from 'react';
import type {Seat} from '@/lib/cinema/types';
import {money,seatKind,seatPrice} from '@/lib/cinema/domain';

type Props={seats:Seat[];selected?:string[];onSelect?:(seat:Seat)=>void;onSelectionChange?:(seats:Seat[])=>void;base?:number;editable?:boolean;rows?:number;columns?:number;showEmpty?:boolean};
type Gesture={pointerId:number;x:number;y:number;localX:number;localY:number;anchor:string;initial:string[];remove:boolean;moved:boolean};
export function SeatGrid({seats,selected=[],onSelect,onSelectionChange,base=0,editable=false,rows,columns:width,showEmpty=false}:Props){
 const columns=width||Math.max(1,...seats.map(s=>s.col_no+(s.kind==='couple'?1:0))),rowCount=rows||Math.max(1,...seats.map(s=>s.row_no));
 const aisle=columns>=10?6:Math.floor(columns/2),gridCol=(col:number)=>col+1+(col>aisle?1:0);
 const gesture=useRef<Gesture|null>(null),ignoreClick=useRef(false),[rectangle,setRectangle]=useState<{left:number;top:number;width:number;height:number}|null>(null);
 const all=[...seats];
 if(showEmpty)for(let row=1;row<=rowCount;row++)for(let col=1;col<=columns;col++){
  if(seats.some(s=>s.row_no===row&&s.col_no<=col&&s.col_no+(s.kind==='couple'?1:0)>=col))continue;
  all.push({id:'empty:'+row+':'+col,label:String.fromCharCode(64+row)+col,row_no:row,col_no:col,kind:'standard',status:'available'});
 }
 function begin(event:React.PointerEvent<HTMLDivElement>){
  if(!editable||!onSelectionChange||!event.isPrimary||event.button!==0)return;
  const button=(event.target as HTMLElement).closest<HTMLButtonElement>('button[data-seat-id]');if(!button)return;
  const anchor=button.dataset.seatId!;ignoreClick.current=false;
  const bounds=event.currentTarget.getBoundingClientRect();
  gesture.current={pointerId:event.pointerId,x:event.clientX,y:event.clientY,localX:event.clientX-bounds.left,localY:event.clientY-bounds.top,anchor,initial:[...selected],remove:selected.includes(anchor),moved:false};
  event.currentTarget.setPointerCapture(event.pointerId);
 }
 function move(event:React.PointerEvent<HTMLDivElement>){
  const drag=gesture.current;if(!drag||drag.pointerId!==event.pointerId)return;
  if(!drag.moved&&Math.hypot(event.clientX-drag.x,event.clientY-drag.y)<5)return;
  drag.moved=true;ignoreClick.current=true;event.preventDefault();
  const layout=event.currentTarget,scroll=layout.parentElement!;
  const bounds=scroll.getBoundingClientRect();if(event.clientX<bounds.left+24)scroll.scrollLeft-=14;else if(event.clientX>bounds.right-24)scroll.scrollLeft+=14;
  const box=layout.getBoundingClientRect(),anchorX=box.left+drag.localX,anchorY=box.top+drag.localY,left=Math.min(anchorX,event.clientX),top=Math.min(anchorY,event.clientY),right=Math.max(anchorX,event.clientX),bottom=Math.max(anchorY,event.clientY);
  const hits=new Set([drag.anchor]);
  for(const button of layout.querySelectorAll<HTMLButtonElement>('button[data-seat-id]')){const r=button.getBoundingClientRect();if(r.left<=right&&r.right>=left&&r.top<=bottom&&r.bottom>=top)hits.add(button.dataset.seatId!);}
  const ids=new Set(drag.initial);for(const id of hits)if(drag.remove)ids.delete(id);else ids.add(id);
  onSelectionChange?.(all.filter(seat=>ids.has(seat.id)));
  setRectangle({left:Math.max(0,left-box.left),top:Math.max(0,top-box.top),width:Math.max(0,Math.min(right,box.right)-Math.max(left,box.left)),height:Math.max(0,Math.min(bottom,box.bottom)-Math.max(top,box.top))});
 }
 function end(event:React.PointerEvent<HTMLDivElement>){const drag=gesture.current;if(drag?.pointerId!==event.pointerId)return;if(!drag.moved&&event.type==='pointerup'){const seat=all.find(s=>s.id===drag.anchor);if(seat)onSelect?.(seat);ignoreClick.current=true;}gesture.current=null;setRectangle(null);if(event.currentTarget.hasPointerCapture(event.pointerId))event.currentTarget.releasePointerCapture(event.pointerId);}
 function click(event:React.MouseEvent<HTMLButtonElement>,seat:Seat){if(ignoreClick.current&&event.detail!==0){ignoreClick.current=false;return;}onSelect?.(seat);}
 return <div className={'seat-map '+(editable?'seat-editor':'')}><div className="screen"/><p className="screen-label">MÀN HÌNH</p><div className="seat-scroll" tabIndex={0} aria-label="Sơ đồ ghế, có thể cuộn ngang để xem đầy đủ"><div className={'seat-layout '+(onSelectionChange?'drag-selectable':'')} style={{gridTemplateColumns:'20px repeat('+aisle+',minmax(34px,1fr)) 12px repeat('+(columns-aisle)+',minmax(34px,1fr)) 20px'}} onPointerDown={begin} onPointerMove={move} onPointerUp={end} onPointerCancel={end} onLostPointerCapture={end}>
  {Array.from({length:rowCount},(_,i)=>i+1).flatMap(row=>[<span key={'left'+row} className="seat-row-label" style={{gridRow:row,gridColumn:1}}>{String.fromCharCode(64+row)}</span>,<span key={'right'+row} className="seat-row-label" style={{gridRow:row,gridColumn:columns+3}}>{String.fromCharCode(64+row)}</span>])}
  {all.map(seat=>{const empty=seat.id.startsWith('empty:'),chosen=selected.includes(seat.id),state=chosen?'selected':seat.status||'available',icon=chosen?'imgBiuTngGh4':state==='sold'?'imgBiuTngGh1':state==='held'?'imgBiuTngGh3':'imgBiuTngGh',span=seat.kind==='couple'?(seat.col_no===aisle?3:2):1;
   return <button key={seat.id} data-seat-id={seat.id} type="button" className={'seat '+(empty?'empty-seat':seat.kind)+' '+state} style={{gridRow:seat.row_no,gridColumn:gridCol(seat.col_no)+' / span '+span,width:'100%'}} disabled={!onSelect||(!editable&&seat.status!=='available')} aria-pressed={chosen} aria-label={empty?'Ô trống '+seat.label:seat.label+', ghế '+seatKind(seat.kind)+(editable?'':', '+money(seatPrice(base,seat.kind))+', '+(chosen?'đang chọn':state==='sold'?'đã bán':state==='held'?'đang giữ':state==='blocked'?'đã khóa':'trống'))} onClick={event=>click(event,seat)}>{empty?'+':<><img src={'/figma/'+icon+'.svg'} width="14" height="12" alt=""/>{seat.label}</>}</button>;
  })}{rectangle&&<div className="seat-selection-rectangle" style={rectangle} aria-hidden="true"/>}
 </div></div>{editable?<div className="seat-kind-legend" aria-label="Chú thích loại ghế">{[['standard','Thường'],['vip','VIP'],['couple','Đôi · 2 chỗ'],['aisle','Lối đi']].map(([kind,label])=><span key={kind}><i className={kind} aria-hidden="true"/>{label}</span>)}</div>:<><p className="seat-caption muted">Thường × 1,0 · VIP × 1,2 · Đôi × 2,0 · Ghế đôi có 2 chỗ/đơn vị</p><div className="legend"><span>Trống</span><span className="accent">Đang chọn</span><span style={{color:'#f5cf79'}}>Đang giữ</span><span className="muted">Đã bán</span>{seats.some(s=>s.status==='blocked')&&<span className="muted">Khóa</span>}</div></>}</div>;
}
