import { notFound } from 'next/navigation';
import { SetupScreen } from '@/components/cinema/setup';
export const dynamic = 'force-dynamic';
export default function Page() {
  if (process.env.NODE_ENV !== 'development') notFound();
  return <SetupScreen />;
}
