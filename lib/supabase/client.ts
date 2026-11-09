import {createClient as createDatabaseClient} from '@supabase/supabase-js';
import {requireSupabaseConfig} from './config';
export function createClient(){const config=requireSupabaseConfig();return createDatabaseClient(config.url,config.key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});}
