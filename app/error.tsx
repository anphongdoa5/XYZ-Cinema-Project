"use client";
import Link from 'next/link';
import {Shell,Heading,Button} from '@/components/cinema/ui';
export default function ErrorPage({retry}:{retry:()=>void}){
 return <Shell><main className="page stack"><Heading label="XYZ CINEMA" title="Chưa thể tải trang này" description="Vui lòng thử lại. Bạn có thể kiểm tra đơn trong lịch sử trước khi thực hiện lại thao tác thanh toán."/><div className="row"><Button onClick={retry}>Thử lại</Button><Button asChild variant="outline"><Link href="/tai-khoan/don-ve">Kiểm tra đơn của tôi</Link></Button><Button asChild variant="outline"><Link href="/">Về trang chủ</Link></Button></div></main></Shell>;
}
