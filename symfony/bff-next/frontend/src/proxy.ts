import { createAuthProxy } from '@kematjaya/auth-ui/proxy';
import { accessRules } from '@/config/access-control';
import { authConfig } from '@/config/auth';

export const proxy = createAuthProxy(authConfig, { accessRules });

export const config = {
    matcher: ['/dashboard/:path*']
};
