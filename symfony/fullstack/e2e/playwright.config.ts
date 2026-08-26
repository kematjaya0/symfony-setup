import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: 'html',
  use: {
    // Di dalam Docker (profile e2e) -> http://php:8082 (lihat compose.yaml).
    // Dijalankan native dari host -> gunakan http://localhost:8082.
    baseURL: process.env.BASE_URL ?? 'http://localhost:8082',
    ignoreHTTPSErrors: true,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
});
