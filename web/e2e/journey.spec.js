// Recorrido completo del usuario (12-10): el mismo test corre local (vite dev) y contra un Preview
// real (E2E_BASE_URL [+ E2E_BYPASS]). Contra el Preview vale la pena de verdad: la CSP de vercel.json
// no existe en `vite dev`, y acá cualquier `securitypolicyviolation` hace fallar el recorrido.
import { test, expect } from '@playwright/test';
import { ID } from '../src/test/fixtures.js';
import { mockApi, KEY } from './mock-api.js';

const panel = (page) => page.getByRole('complementary', { name: 'Detalle del elemento seleccionado' });

test('recorrido completo: acceso, mapa, filtro, obra, path, trigger, Obras, Artistas y salir (sin violaciones de CSP)', async ({ page }) => {
  const csp = [];
  await page.exposeFunction('__cspHit', (v) => csp.push(v));
  await page.addInitScript(() =>
    document.addEventListener('securitypolicyviolation', (e) =>
      window.__cspHit(`${e.violatedDirective} ${e.blockedURI}`)),
  );
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => /content security policy|refused to/i.test(m.text()) && csp.push(m.text()));
  await mockApi(page); // red y tiles mockeados: corre igual local y remoto

  // 1. Acceso
  await page.goto('/');
  await expect(page).toHaveURL(/\/acceso$/);
  await page.getByLabel('API key').fill(KEY);
  await page.getByRole('button', { name: 'Entrar a la web' }).click();
  await expect(page).toHaveURL(/\/$/);

  // 2. Mapa: pill honesta y leyenda con los conteos de las fixtures
  await expect(page.locator('.pill')).toContainText('Sync al día');
  await expect(page.locator('.legend')).toHaveText('3 obras · 3 paths · 35 triggers · 1 portal');
  await expect(page.locator('path.cg-cover')).toHaveCount(2);

  // 3. Filtro de recorrido: abre su panel con créditos
  await page.getByRole('combobox', { name: 'Recorrido' }).selectOption(ID.rec1);
  await expect(panel(page).getByRole('heading', { name: 'Recorrido Norte' })).toBeVisible();
  await expect(panel(page).getByText('Créditos', { exact: true })).toBeVisible();

  // 4. Obra A, expandida, y su path de 32 triggers
  await page.getByRole('button', { name: 'Obra Obra Aurora' }).dispatchEvent('click');
  await expect(panel(page).getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
  await page.getByRole('button', { name: 'Ver detalle completo' }).click();
  await panel(page).getByRole('button', { name: /^Ruta A/ }).click();
  const p = panel(page);
  await expect(p.getByRole('heading', { name: 'Ruta A' })).toBeVisible();
  await expect(p.getByRole('img', { name: '32 triggers, 1 hueco' })).toBeVisible();
  await expect(p.getByText('Audio del path')).toBeVisible();

  // 5. Trigger 001 (círculo del mapa) y Siguiente
  await page.getByRole('button', { name: 'Círculos' }).click();
  await page.getByRole('button', { name: 'Trigger 1 de 32, radio 12 m' }).dispatchEvent('click');
  await expect(p.getByRole('heading', { name: 'Trigger 001' })).toBeVisible();
  await p.getByRole('button', { name: /Siguiente/ }).click();
  await expect(p.getByRole('heading', { name: 'Trigger 002' })).toBeVisible();

  // 6. Obras: filtro por Pública, abrir A (breadcrumb y mini-mapa)
  const nav = page.getByRole('navigation', { name: 'Secciones' });
  await nav.getByRole('link', { name: 'Obras' }).click();
  await page.getByLabel('Visibilidad').selectOption('public');
  await page.getByRole('list', { name: 'Listado de obras' }).getByRole('link', { name: /Obra Aurora/ }).click();
  const d = page.getByRole('region', { name: 'Detalle' });
  await expect(d.getByRole('navigation', { name: 'Ruta' })).toContainText('Obras');
  await expect(d.getByRole('img', { name: 'Mapa de Obra Aurora' })).toBeVisible();

  // 7. Artistas: el artista con bio
  await nav.getByRole('link', { name: 'Artistas' }).click();
  await page.getByRole('list', { name: 'Listado de artistas' }).getByRole('link', { name: /Ana Lúcar/ }).click();
  await expect(page).toHaveURL(new RegExp(`/artistas/${ID.arA}$`));
  await expect(d.getByRole('heading', { name: 'Ana Lúcar' })).toBeVisible();
  await expect(d.getByText('Bio de prueba.')).toBeVisible();

  // 8. Salir de la web
  await page.getByRole('button', { name: 'Salir de la web' }).click();
  await expect(page).toHaveURL(/\/acceso$/);
  expect(await page.evaluate(() => sessionStorage.length)).toBe(0);

  // Los Previews de Vercel inyectan su widget de feedback (vercel.live); la CSP lo bloquea a propósito y en
  // Production no existe. Cualquier otra violación sí hace fallar el recorrido.
  const propias = csp.filter((v) => !/vercel\.live/.test(v));
  expect(propias, 'violaciones de CSP').toEqual([]);
  expect(errors, 'errores no capturados').toEqual([]);
});
