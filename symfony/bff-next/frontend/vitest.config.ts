import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
    plugins: [react()],
    test: {
        environment: 'jsdom',
        setupFiles: ['./vitest.setup.ts'],
        globals: true,
        exclude: ['tests/e2e/**', 'node_modules/**'],
        // Force this package through Vite's normal transform pipeline instead of
        // esbuild's dep-optimizer fast path — otherwise vi.mock('next/link', ...)
        // doesn't intercept the package's own internal `next/link` import (used by
        // MenuNav, bundled into the same entry as everything else it exports).
        server: {
            deps: {
                inline: ['@kematjaya/access-control-ui']
            }
        }
    },
    resolve: {
        alias: {
            '@': new URL('./src', import.meta.url).pathname
        }
    }
});
