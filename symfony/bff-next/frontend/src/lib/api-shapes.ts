import type { TokenPair } from '@/types/api';

export function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

export function isTokenPair(value: unknown): value is TokenPair {
    return (
        isRecord(value) &&
        typeof value.token === 'string' &&
        typeof value.refresh_token === 'string'
    );
}
