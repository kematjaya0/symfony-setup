import type { Problem } from '@/types/api';

export const apiBase = () =>
    process.env.API_INTERNAL_URL ?? 'http://127.0.0.1:8000';
export const appOrigin = () =>
    process.env.APP_ORIGIN ?? 'http://127.0.0.1:3000';
export const accessCookieName = () =>
    process.env.NODE_ENV === 'production'
        ? '__Host-access_token'
        : 'access_token';
export const refreshCookieName = () =>
    process.env.NODE_ENV === 'production'
        ? '__Host-refresh_token'
        : 'refresh_token';

export function cookieOptions(maxAge?: number) {
    return {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'lax' as const,
        path: '/',
        ...(maxAge === undefined ? {} : { maxAge })
    };
}

export function validateOrigin(request: Request): Response | null {
    const origin = request.headers.get('origin');
    if (origin !== appOrigin())
        return jsonProblem(403, {
            title: 'Forbidden',
            detail: 'Invalid origin.'
        });
    return null;
}

export async function parseJson<T>(
    request: Request,
    schema: {
        safeParse: (
            value: unknown
        ) => { success: true; data: T } | { success: false };
    }
) {
    let data: unknown;
    try {
        data = await request.json();
    } catch {
        return {
            error: jsonProblem(400, {
                title: 'Bad Request',
                detail: 'Invalid JSON.'
            })
        };
    }
    const parsed = schema.safeParse(data);
    if (!parsed.success)
        return {
            error: jsonProblem(422, {
                title: 'Validation Failed',
                detail: 'Invalid input.'
            })
        };
    return { data: parsed.data };
}

export function jsonProblem(status: number, problem: Problem) {
    return Response.json(problem, { status, headers: noStoreHeaders() });
}

export function noStoreHeaders() {
    return { 'Cache-Control': 'no-store' };
}

export function safeJsonResponse(data: unknown, status: number) {
    if (status === 204)
        return new Response(null, { status, headers: noStoreHeaders() });
    return Response.json(data, { status, headers: noStoreHeaders() });
}

export async function backendFetch(
    path: string,
    init: RequestInit,
    token?: string
) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10_000);
    try {
        return await fetch(`${apiBase()}${path}`, {
            ...init,
            cache: 'no-store',
            signal: controller.signal,
            headers: {
                accept: 'application/ld+json, application/json',
                ...(init.body
                    ? {
                          'content-type':
                              init.method === 'PATCH'
                                  ? 'application/merge-patch+json'
                                  : 'application/json'
                      }
                    : {}),
                ...(token ? { authorization: `Bearer ${token}` } : {})
            }
        });
    } finally {
        clearTimeout(timeout);
    }
}

function sanitizeUpstreamError(data: Record<string, unknown>): Record<string, unknown> {
    const keep = new Set(['type', 'title', 'status', 'detail', 'violations']);
    const cleaned: Record<string, unknown> = {};
    for (const key of Object.keys(data)) {
        if (keep.has(key)) {
            if (key === 'violations' && Array.isArray(data[key])) {
                cleaned[key] = data[key].map((v: unknown) => {
                    if (v && typeof v === 'object' && !Array.isArray(v)) {
                        const violation = v as Record<string, unknown>;
                        const { parameters, template, ...rest } = violation;
                        return rest;
                    }
                    return v;
                });
            } else {
                cleaned[key] = data[key];
            }
        }
    }
    return cleaned;
}

export async function backendJson(response: Response) {
    if (response.status === 204) return null;
    const text = await response.text();
    if (!text) return null;
    try {
        const parsed = JSON.parse(text) as unknown;
        if (
            response.status >= 400 &&
            parsed &&
            typeof parsed === 'object' &&
            !Array.isArray(parsed)
        ) {
            return sanitizeUpstreamError(parsed as Record<string, unknown>);
        }
        return parsed;
    } catch {
        return { title: response.statusText || 'Upstream error' };
    }
}
