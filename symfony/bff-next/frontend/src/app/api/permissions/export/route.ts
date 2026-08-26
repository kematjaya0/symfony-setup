import type { NextRequest } from 'next/server';
import { authedBackend } from '@/lib/bff';
import { parseJson, validateOrigin } from '@/lib/http';
import { permissionsExportSchema } from '@/lib/schemas';

export async function POST(request: NextRequest) {
    const badOrigin = validateOrigin(request);
    if (badOrigin) return badOrigin;
    const parsed = await parseJson(request, permissionsExportSchema);
    if ('error' in parsed) return parsed.error;
    return authedBackend('/api/permissions/export', {
        method: 'POST',
        body: JSON.stringify(parsed.data),
    });
}
export const dynamic = 'force-dynamic';
export const revalidate = 0;
