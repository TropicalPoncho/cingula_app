import { test, expect } from '@playwright/test';
import { makeRows } from '../src/test/fixtures.js';
import { mockApi, loginAs } from './mock-api.js';

test('2 páginas: la pill termina en "Sync al día" con el cursor de la última página tal cual', async ({ page }) => {
  const rows = makeRows();
  await mockApi(page, { rows, limit: 30 });
  await loginAs(page);
  await page.goto('/');
  const pill = page.locator('.pill');
  await expect(pill).toContainText('Sync al día · pull hace');
  await expect(pill).toContainText(`cursor ${rows.at(-1).change_seq}`);
});

test('falla en la página 2: "Error de pull · sin datos" y nada a medias', async ({ page }) => {
  await mockApi(page, { limit: 30, failPage: 2 });
  await loginAs(page);
  await page.goto('/');
  await expect(page.locator('.pill')).toContainText('Error de pull · sin datos');
});

test('la leyenda cuenta sólo lo vivo: sin la obra D, sus hijos ni el trigger borrado', async ({ page }) => {
  await mockApi(page);
  await loginAs(page);
  await page.goto('/');
  await expect(page.locator('.legend')).toHaveText('3 obras · 3 paths · 35 triggers · 1 portal');
});

test('sin filas: "Todavía no hay obras en el servidor."', async ({ page }) => {
  await mockApi(page, { rows: [] });
  await loginAs(page);
  await page.goto('/');
  await expect(page.getByText('Todavía no hay obras en el servidor.')).toBeVisible();
  await expect(page.getByText('Cuando el celular sincronice la primera obra, va a aparecer acá.')).toBeVisible();
});

test('primer pull fallido: bloque de error con código y "Reintentar lectura" que vuelve a leer', async ({ page }) => {
  await mockApi(page, { failPage: 1, failStatus: 503 });
  await loginAs(page);
  await page.goto('/');
  const alert = page.getByRole('alert');
  await expect(alert).toContainText('No se pudo leer el servidor.');
  await expect(alert).toContainText('GET /sync/pull → 503. Revisá tu conexión y reintentá.');
  await page.getByRole('button', { name: 'Reintentar lectura' }).click();
  await expect(page.locator('.legend')).toContainText('3 obras');
});

test('401 en el pull: borra la clave y va a /acceso?motivo=401', async ({ page }) => {
  await mockApi(page, { failPage: 1, failStatus: 401 });
  await loginAs(page);
  await page.goto('/');
  await expect(page).toHaveURL(/\/acceso\?motivo=401$/);
  expect(await page.evaluate(() => sessionStorage.length)).toBe(0);
});
