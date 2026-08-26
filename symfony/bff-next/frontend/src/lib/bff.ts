import { cookies } from 'next/headers';
import { isTokenPair } from './api-shapes';
import type { TokenPair } from '@/types/api';
import {
    accessCookieName,
    backendFetch,
    backendJson,
    cookieOptions,
    noStoreHeaders,
    refreshCookieName,
    safeJsonResponse
} from './http';

export async function setTokenCookies(tokens: TokenPair) {
    const jar = await cookies();
    jar.set(accessCookieName(), tokens.token, cookieOptions(900));
    jar.set(
        refreshCookieName(),
        tokens.refresh_token,
        cookieOptions(60 * 60 * 24 * 30)
    );
}

export async function refreshTokens() {
    const jar = await cookies();
    const refreshToken = jar.get(refreshCookieName())?.value;
    if (!refreshToken) return false;
    const response = await backendFetch('/api/token/refresh', {
        method: 'POST',
        body: JSON.stringify({ refresh_token: refreshToken })
    });
    if (!response.ok) return false;
    const data = await backendJson(response);
    if (!isTokenPair(data)) return false;
    await setTokenCookies(data);
    return true;
}

export async function authedBackend(path: string, init: RequestInit = {}) {
    const jar = await cookies();
    const token = jar.get(accessCookieName())?.value;
    let response = await backendFetch(path, init, token);
    if (response.status === 401 && (await refreshTokens())) {
        const freshToken = (await cookies()).get(accessCookieName())?.value;
        response = await backendFetch(path, init, freshToken);
    }
    if (response.status === 401) {
        return safeJsonResponse(await backendJson(response), 401);
    }
    return safeJsonResponse(await backendJson(response), response.status);
}

export function tokenlessAuthResponse() {
    return Response.json(
        { ok: true },
        { status: 200, headers: noStoreHeaders() }
    );
}

export { isTokenPair };
