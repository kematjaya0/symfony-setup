import { createLogoutRoute } from '@kematjaya/auth-ui/routes';
import { authConfig } from '@/config/auth';

export const POST = createLogoutRoute(authConfig);
export const dynamic = 'force-dynamic';
export const revalidate = 0;
