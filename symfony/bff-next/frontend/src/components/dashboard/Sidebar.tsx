'use client';

import Link from 'next/link';
import { MenuNav } from '@kematjaya/access-control-ui';
import { defineMenuNavConfig } from '@kematjaya/access-control-ui/config';
import type { MenuSection } from '@kematjaya/access-control-ui/types';

const menuNavConfig = defineMenuNavConfig({
    isActive: (href, pathname) => (href === '/dashboard' ? pathname === '/dashboard' : pathname.startsWith(href))
});

export function Sidebar({ items }: { items: MenuSection[] }) {
    return (
        <aside className="dashboard-sidebar">
            <Link href="/dashboard" className="sidebar-logo">
                <span className="logo-icon">D</span>
                <span>Dashboard</span>
            </Link>

            <MenuNav items={items} config={menuNavConfig} />
        </aside>
    );
}
