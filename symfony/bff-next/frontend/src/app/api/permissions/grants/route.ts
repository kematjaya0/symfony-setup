import type { NextRequest } from 'next/server';
import { authedBackend } from '@/lib/bff';
import { parseJson, validateOrigin } from '@/lib/http';
import { permissionsGrantSchema } from '@/lib/schemas';

export async function PUT(request: NextRequest) {
    const badOrigin = validateOrigin(request);
    if (badOrigin) return badOrigin;
    const parsed = await parseJson(request, permissionsGrantSchema);
    if ('error' in parsed) return parsed.error;
    return authedBackend('/api/permissions/grants', {
        method: 'PUT',
        body: JSON.stringify(parsed.data),
    });
}
export const dynamic = 'force-dynamic';
export const revalidate = 0;
