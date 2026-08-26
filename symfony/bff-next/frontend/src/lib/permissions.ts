import { authedBackend } from '@/lib/bff';
import { createRequirePermission } from '@kematjaya/access-control-ui/guards';
import type { MenuSection, MePermissions } from '@kematjaya/access-control-ui/types';

export async function getMyPermissionKeys(): Promise<string[]> {
    const response = await authedBackend('/api/me/permissions');
    if (!response.ok) return [];
    const data = (await response.json()) as MePermissions;
    return Array.isArray(data.keys) ? data.keys : [];
}

// Menu is already role/permission-filtered server-side (MenuController) —
// the frontend just renders whatever sections/items come back.
export async function getMenu(): Promise<MenuSection[]> {
    const response = await authedBackend('/api/me/menu');
    if (!response.ok) return [];
    const data = (await response.json()) as MenuSection[];
    return Array.isArray(data) ? data : [];
}

// Server-component guard: mirrors the ROLE_ADMIN check already used by
// admin/page.tsx, but for a dynamic permission key. Menu/button hiding is
// cosmetic only — this is the actual boundary for direct URL access.
export const requirePermission = createRequirePermission(getMyPermissionKeys);
