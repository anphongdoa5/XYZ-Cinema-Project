import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
import { publicSupabaseConfig } from './supabase/config';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export const hasEnvVars = publicSupabaseConfig().ok;
