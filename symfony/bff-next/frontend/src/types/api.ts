import type { components, paths } from './api.generated';

type Json<T> = T extends { 'application/json': infer V } ? V : never;

type LoginResponses = paths['/api/login']['post']['responses'];

/**
 * Backend token-pair shape, kept here (not imported from @kematjaya/auth-ui)
 * because `lib/bff.ts`'s `authedBackend()` — used by every BFF route that
 * needs refresh-on-401 — depends on it independently of auth-ui.
 */
export type TokenPair = NonNullable<Json<LoginResponses[200]['content']>> & {
    refresh_token: string;
};
export type Problem =
    | components['schemas']['Error']
    | components['schemas']['ConstraintViolation']
    | { title?: string; detail?: string };

// Permission/menu types (PermissionMatrixData, MePermissions, MenuSection, ...)
// now live in @kematjaya/access-control-ui/types.
