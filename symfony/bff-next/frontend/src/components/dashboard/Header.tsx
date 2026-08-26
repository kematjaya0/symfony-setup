'use client';

import type { UserProfile } from '@kematjaya/auth-ui';
import {
    DropdownDivider,
    DropdownHeader,
    DropdownItem,
    DropdownLinkItem,
    DropdownMenu,
    useDropdown
} from '@kematjaya/bootstrap-ui-kit';
import { useRouter, usePathname } from 'next/navigation';

const notifications = [
    { id: 1, icon: 'bi-info-circle', text: 'Welcome to your dashboard', time: '2 min ago', color: 'var(--color-electric-blue)' },
    { id: 2, icon: 'bi-person', text: 'Profile picture updated successfully', time: '1 hr ago', color: 'var(--color-lavender)' },
    { id: 3, icon: 'bi-check2-circle', text: 'Task "Review PR #42" completed', time: '3 hr ago', color: 'var(--color-vivid-green)' }
];

const breadcrumbLabels: Record<string, string> = {
    '/dashboard': 'Dashboard',
    '/dashboard/admin': 'Admin',
    '/dashboard/profile': 'Profile'
};

function displayName(email: string) {
    return email.split('@')[0] || email;
}

function initials(email: string) {
    const name = displayName(email);
    const parts = name.split(/[._-]+/).filter(Boolean);
    const letters =
        parts.length > 1
            ? `${parts[0]?.[0] ?? ''}${parts[1]?.[0] ?? ''}`
            : name.slice(0, 2);
    return letters.toUpperCase();
}

export function Header({ user }: { user: UserProfile }) {
    const pathname = usePathname();
    const router = useRouter();
    const currentLabel = breadcrumbLabels[pathname] || 'Dashboard';
    const [notifMenu, notifMenuRef] = useDropdown();
    const [userMenu, userMenuRef] = useDropdown();

    async function handleLogout() {
        userMenu.close();
        try {
            await fetch('/api/auth/logout', { method: 'POST' });
        } catch {
            // proceed to redirect even on network error
        }
        router.push('/login?toast=berhasil+logout');
    }

    return (
        <header className="dashboard-header">
            <div className="header-left">
                <div className="header-breadcrumb">
                    Pages / <span>{currentLabel}</span>
                </div>
            </div>

            <div className="header-right">
                <div className="dropdown dashboard-dropdown notif-dropdown" ref={notifMenuRef}>
                    <button
                        className="header-btn"
                        aria-expanded={notifMenu.open}
                        aria-label="Notifications"
                        onClick={notifMenu.toggle}
                    >
                        <i className="bi bi-bell" />
                        <span className="notification-dot" />
                    </button>
                    <DropdownMenu open={notifMenu.open}>
                        <DropdownHeader>Notifications</DropdownHeader>
                        {notifications.map((n) => (
                            <li key={n.id}>
                                <span className="dropdown-item notif-item">
                                    <span className="notif-icon">
                                        <i className={`bi ${n.icon}`} style={{ color: n.color }} />
                                    </span>
                                    <span className="notif-text">{n.text}</span>
                                    <span className="notif-time">{n.time}</span>
                                </span>
                            </li>
                        ))}
                        <DropdownDivider />
                        <li>
                            <span className="dropdown-item" style={{ justifyContent: 'center', color: 'var(--color-electric-blue)', fontWeight: 500 }}>
                                View all
                            </span>
                        </li>
                    </DropdownMenu>
                </div>

                <div className="dropdown dashboard-dropdown" ref={userMenuRef}>
                    <button
                        className="user-btn"
                        aria-haspopup="true"
                        aria-expanded={userMenu.open}
                        aria-label="User menu"
                        onClick={userMenu.toggle}
                    >
                        <span className="user-avatar">{initials(user.email)}</span>
                        <span>{displayName(user.email)}</span>
                        <i className="bi bi-chevron-down" style={{ fontSize: 12, color: 'var(--color-fog)' }} />
                    </button>
                    <DropdownMenu open={userMenu.open} role="menu">
                        <li><span className="dropdown-item-header" style={{ padding: '8px 12px 0', fontSize: 13, color: 'var(--color-fog)' }}>{user.email}</span></li>
                        <DropdownDivider />
                        <DropdownLinkItem href="/dashboard/profile" onClick={userMenu.close}>
                            <i className="bi bi-person" /> Profile
                        </DropdownLinkItem>
                        <DropdownDivider />
                        <DropdownItem
                            style={{ color: 'var(--color-tangerine)' }}
                            onClick={handleLogout}
                        >
                            <i className="bi bi-box-arrow-right" /> Sign out
                        </DropdownItem>
                    </DropdownMenu>
                </div>
            </div>
        </header>
    );
}
