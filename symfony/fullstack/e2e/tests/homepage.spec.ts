import { test, expect } from '@playwright/test';

test('homepage merespons dan punya title', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(/./);
});
