import { z } from 'zod';

export const permissionsExportSchema = z.object({
    profile: z.string().optional()
});

export const permissionsGrantSchema = z.object({
    roleCode: z.string().min(1),
    permissionKeys: z.array(z.string())
});
