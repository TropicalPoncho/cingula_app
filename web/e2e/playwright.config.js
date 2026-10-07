import { defineConfig, devices } from '@playwright/test';

// Modo remoto (12-10): E2E_BASE_URL apunta a un Preview ya desplegado (sin webServer). Si el Preview
// tiene Deployment Protection, E2E_BYPASS manda el header de bypass; el valor sólo vive en la sesión.
const remote = process.env.E2E_BASE_URL;
const bypass = process.env.E2E_BYPASS;

export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.js',
  reporter: 'list',
  use: {
    baseURL: remote ?? 'http://localhost:5173',
    ...(remote && bypass && { extraHTTPHeaders: { 'x-vercel-protection-bypass': bypass } }),
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  ...(!remote && {
    webServer: {
      command: 'npx vite --port 5173 --strictPort',
      cwd: '..', // web/
      url: 'http://localhost:5173',
      reuseExistingServer: true,
    },
  }),
});
