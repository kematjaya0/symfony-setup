import { defineAuthConfig } from '@kematjaya/auth-ui/config';

export const authConfig = defineAuthConfig({
    backendBaseUrl: process.env.API_INTERNAL_URL ?? 'http://127.0.0.1:8000',
    appOrigin: process.env.APP_ORIGIN ?? 'http://127.0.0.1:3000'
});
