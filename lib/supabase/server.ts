import 'server-only';
import {createClient as createDatabaseClient} from '@supabase/supabase-js';
import {cookies} from 'next/headers';
import {requireSupabaseConfig} from './config';
import {sessionCookie,type SessionScope} from '@/lib/cinema/session';
export async function createClient(scope:SessionScope='customer'){
 const config=requireSupabaseConfig();const store=await cookies();
 return createDatabaseClient(config.url,config.key,{
  auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},
  global:{headers:{'x-cinema-session':store.get(sessionCookie(scope))?.value||''}},
 });
}
