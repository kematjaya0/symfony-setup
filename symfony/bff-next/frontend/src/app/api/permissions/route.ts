import { authedBackend } from '@/lib/bff';
export async function GET() {
    return authedBackend('/api/permissions');
}
export const dynamic = 'force-dynamic';
export const revalidate = 0;
