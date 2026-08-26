import { describe, expect, it, vi } from 'vitest';
import { isTokenPair, tokenlessAuthResponse } from '@/lib/bff';
import { cookieOptions, validateOrigin } from '@/lib/http';

describe('bff helpers', () => {
    it('detects backend token pairs', () => {
        expect(isTokenPair({ token: 'a', refresh_token: 'b' })).toBe(true);
        expect(isTokenPair({ token: 'a' })).toBe(false);
    });

    it('uses HttpOnly lax cookies', () => {
        expect(cookieOptions(1)).toMatchObject({
            httpOnly: true,
            sameSite: 'lax',
            path: '/',
            maxAge: 1
        });
    });

    it('rejects unsafe origin mismatch', () => {
        vi.stubEnv('APP_ORIGIN', 'http://app.test');
        const request = new Request('http://app.test/api/example', {
            method: 'POST',
            headers: { origin: 'http://evil.test' }
        });
        expect(validateOrigin(request)).not.toBeNull();
        vi.unstubAllEnvs();
    });

    it('does not expose backend tokens in auth success JSON', async () => {
        const response = tokenlessAuthResponse();
        expect(response.status).toBe(200);
        await expect(response.json()).resolves.toEqual({ ok: true });
    });
});
