import { createMeRoute } from '@kematjaya/auth-ui/routes';
import { authConfig } from '@/config/auth';

export const GET = createMeRoute(authConfig);
export const dynamic = 'force-dynamic';
export const revalidate = 0;
