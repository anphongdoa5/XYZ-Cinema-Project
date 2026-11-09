"use client";
import {api} from './cinema/ui';
export function LogoutButton(){return <button onClick={async()=>{await api('logout',{});window.location.assign('/');}}>Đăng xuất</button>;}
