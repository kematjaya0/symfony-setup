import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
    testDir: './tests/e2e',
    retries: process.env.CI ? 1 : 0,
    use: {
        baseURL: process.env.PLAYWRIGHT_BASE_URL ?? 'http://127.0.0.1:3000',
        trace: 'on-first-retry'
    },
    webServer: process.env.PLAYWRIGHT_SKIP_WEB_SERVER
        ? undefined
        : {
              command: 'npm run dev',
              url: 'http://127.0.0.1:3000',
              reuseExistingServer: !process.env.CI,
              timeout: 120_000
          },
    projects: [
        {
            name: 'chromium',
            use: { ...devices['Desktop Chrome'] },
            // access-control.spec.ts mutates global, role-level RolePermission
            // grants shared by every ROLE_USER account — it must not overlap
            // with other specs that assume the default grants stay intact.
            testIgnore: /access-control\.spec\.ts$/
        },
        {
            name: 'access-control',
            use: { ...devices['Desktop Chrome'] },
            testMatch: /access-control\.spec\.ts$/,
            dependencies: ['chromium']
        }
    ]
});
