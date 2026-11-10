import Link from 'next/link';
export default function PaymentResult(){return <main className="page stack"><h1>Chưa xác minh được kết quả VNPay</h1><p>Vui lòng kiểm tra trạng thái đơn trong Vé của tôi. Nếu đã thanh toán, đợi hệ thống nhận xác nhận từ VNPay trước khi thử lại.</p><Link className="accent" href="/tai-khoan/don-ve">Về Vé của tôi →</Link></main>;}
