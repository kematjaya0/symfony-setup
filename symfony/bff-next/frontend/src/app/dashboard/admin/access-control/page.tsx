import { getCurrentUser } from '@kematjaya/auth-ui/session';
import { redirect } from 'next/navigation';
import { authConfig } from '@/config/auth';
import { PermissionMatrix } from '@kematjaya/access-control-ui';

export const metadata = { title: 'Access Control — Settings' };

export default async function AccessControlPage() {
    const user = await getCurrentUser(authConfig);
    if (!user || !user.roles.includes('ROLE_ADMIN')) {
        redirect('/access-denied');
    }
    return (
        <div>
            <h1 className="h3 mb-3">Access Control</h1>
            <p className="text-muted mb-4">Manage role permissions for menus and actions.</p>
            <PermissionMatrix />
        </div>
    );
}
