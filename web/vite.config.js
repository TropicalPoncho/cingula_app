import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      // ponytail: el proxy nunca inyecta claves; la clave la tipea el usuario en /acceso.
      '/sync': {
        target: process.env.DEV_API_TARGET ?? 'https://cingula.vercel.app',
        changeOrigin: true,
      },
    },
  },
  test: {
    environment: 'jsdom',
    // No recoge los api/**/*.test.js de node:test.
    include: ['src/**/*.spec.{js,jsx}'],
    setupFiles: ['./src/test-setup.js'],
  },
});
