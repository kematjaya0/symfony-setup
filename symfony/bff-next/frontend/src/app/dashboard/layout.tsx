import { getCurrentUser } from '@kematjaya/auth-ui/session';
import { redirect } from 'next/navigation';
import { Sidebar } from '@/components/dashboard/Sidebar';
import { Header } from '@/components/dashboard/Header';
import { authConfig } from '@/config/auth';
import { getMenu } from '@/lib/permissions';
import { PermissionsProvider } from '@kematjaya/access-control-ui';

export default async function DashboardLayout({
    children
}: Readonly<{ children: React.ReactNode }>) {
    const user = await getCurrentUser(authConfig);
    if (!user) redirect('/login');
    const menu = await getMenu();

    return (
        <PermissionsProvider>
            <div className="dashboard-body">
                <Sidebar items={menu} />
                <Header user={user} />
                <main className="dashboard-main">
                    <div className="dashboard-content">
                        {children}
                    </div>
                </main>
            </div>
        </PermissionsProvider>
    );
}
