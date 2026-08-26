import { getCurrentUser } from '@kematjaya/auth-ui/session';
import { redirect } from 'next/navigation';
import { authConfig } from '@/config/auth';

export default async function AdminPage() {
    const user = await getCurrentUser(authConfig);
    if (!user || !user.roles.includes('ROLE_ADMIN')) {
        redirect('/access-denied');
    }

    return (
        <div>
            <h1>Admin</h1>
            <p>Halaman ini hanya terlihat di menu untuk ROLE_ADMIN.</p>
        </div>
    );
}
