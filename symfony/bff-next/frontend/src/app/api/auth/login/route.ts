import { createLoginRoute } from '@kematjaya/auth-ui/routes';
import { authConfig } from '@/config/auth';

export const POST = createLoginRoute(authConfig);
export const dynamic = 'force-dynamic';
export const revalidate = 0;
