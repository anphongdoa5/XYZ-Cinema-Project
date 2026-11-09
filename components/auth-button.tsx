import Link from 'next/link';
import {identity} from '@/lib/cinema/server';
import {LogoutButton} from './logout-button';
export async function AuthButton(){const {profile}=await identity();return profile?<LogoutButton/>:<Link href="/auth/login">Đăng nhập</Link>;}
