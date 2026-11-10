/** Truncate at a word boundary; Array.from preserves Unicode code points. */
export function shortDescription(value:string,limit=280){
 const text=value.replace(/\s+/g,' ').trim();const characters=Array.from(text);
 if(characters.length<=limit)return text;
 const cut=characters.slice(0,limit-1).join('');const boundary=cut.lastIndexOf(' ');
 return (boundary>cut.length*.7?cut.slice(0,boundary):cut).trimEnd()+'…';
}
