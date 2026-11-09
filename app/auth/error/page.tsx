import Link from 'next/link';
import { Shell,Heading } from '@/components/cinema/ui';
export default function Page(){return <Shell><main className="page stack"><Heading label="TÀI KHOẢN" title="Liên kết không còn hiệu lực"/><p>Hãy yêu cầu liên kết mới hoặc thử đăng nhập lại.</p><Link className="link" href="/auth/login">Về đăng nhập</Link></main></Shell>;}
