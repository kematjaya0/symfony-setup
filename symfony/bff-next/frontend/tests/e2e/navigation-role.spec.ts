import { test, expect, type Locator, type Page } from '@playwright/test';

const password = 'CorrectHorseBatteryStaple!1';

function requiredEnv(name: 'PLAYWRIGHT_ADMIN_EMAIL' | 'PLAYWRIGHT_ADMIN_PASSWORD'): string {
    const value = process.env[name];
    if (!value) {
        throw new Error(`${name} is required`);
    }

    return value;
}

function adminLink(page: Page): Locator {
    return page.locator('.dashboard-sidebar').getByRole('link', { name: 'Admin' });
}

async function login(page: Page, email: string, loginPassword: string): Promise<void> {
    await page.goto('/login');
    await page.getByLabel('Email').fill(email);
    await page.getByLabel('Password').fill(loginPassword);
    await page.getByRole('button', { name: 'Continue' }).click();
    await expect(page).toHaveURL(/\/dashboard$/);
}

test('regular user cannot see or directly access admin dashboard', async ({ page }) => {
    const email = `pw-navigation-${Date.now()}@example.com`;

    await page.goto('/register');
    await page.getByLabel('Email').fill(email);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: 'Create Account' }).click();
    await expect(page).toHaveURL(/\/login$/);

    await login(page, email, password);
    await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();
    await expect(adminLink(page)).toHaveCount(0);

    await page.goto('/dashboard/admin');
    await expect(page).toHaveURL(/\/access-denied$/);
    await expect(page.getByRole('heading', { name: 'Akses Ditolak' })).toBeVisible();
});

test('admin can navigate to admin dashboard', async ({ page }) => {
    const email = requiredEnv('PLAYWRIGHT_ADMIN_EMAIL');
    const adminPassword = requiredEnv('PLAYWRIGHT_ADMIN_PASSWORD');

    await login(page, email, adminPassword);

    const link = adminLink(page);
    await expect(link).toBeVisible();
    await link.click();
    await expect(page).toHaveURL(/\/dashboard\/admin$/);
    await expect(page.getByRole('heading', { name: 'Admin' })).toBeVisible();
});
