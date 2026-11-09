import Link from 'next/link';
import {Shell,Empty,Button} from '@/components/cinema/ui';
export default function NotFound(){return <Shell><main className="page"><Empty title="Không tìm thấy trang" description="Đường dẫn không còn tồn tại. Bạn có thể quay lại để chọn phim hoặc xem đơn đã đặt."><Button asChild><Link href="/">Về trang chủ</Link></Button></Empty></main></Shell>;}
