export type AccessRule = {
    pattern: RegExp;
    roles: string[];
};

// Diperiksa berurutan — aturan PERTAMA yang cocok (path) yang dipakai,
// sama seperti semantik access_control di security.yaml Symfony.
export const accessRules: AccessRule[] = [
    { pattern: /^\/dashboard\/admin(\/|$)/, roles: ['ROLE_ADMIN'] }
];
