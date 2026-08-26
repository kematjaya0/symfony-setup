import { test, expect } from '@playwright/test';

test('logout clears session and shows toast on login page', async ({ page }) => {
    const email = `pw-logout-${Date.now()}@example.com`;
    const password = 'CorrectHorseBatteryStaple!1';

    // Register
    await page.goto('/register');
    await page.getByLabel('Email').fill(email);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: 'Create Account' }).click();
    await expect(page).toHaveURL(/\/login$/);

    // Login
    await page.getByLabel('Email').fill(email);
    await page.getByLabel('Password').fill(password);
    await page.getByRole('button', { name: 'Continue' }).click();
    await expect(page).toHaveURL(/\/dashboard/);

    // Open user dropdown
    await page.getByRole('button', { name: 'User menu' }).click();
    await expect(page.getByRole('menu')).toBeVisible();

    // Click Sign out
    await page.getByRole('menuitem', { name: 'Sign out' }).click();

    // Assert redirect to /login with toast param
    await expect(page).toHaveURL(/\/login\?toast=berhasil\+logout/);

    // Assert toast message is visible
    await expect(page.getByRole('status')).toContainText('berhasil logout');
});
