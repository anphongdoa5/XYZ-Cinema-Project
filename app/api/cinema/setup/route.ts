import { checkSetup } from '@/lib/cinema/setup';
export const dynamic = 'force-dynamic';
export async function GET() {
  if (process.env.NODE_ENV !== 'development') return Response.json({ error: 'Không tìm thấy chức năng.' }, { status: 404 });
  return Response.json(await checkSetup(), { headers: { 'Cache-Control': 'no-store' } });
}
