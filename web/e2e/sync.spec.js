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

test('401 en el pull: borra la clave y va a /acceso?motivo=401', async ({ page }) => {
  await mockApi(page, { failPage: 1, failStatus: 401 });
  await loginAs(page);
  await page.goto('/');
  await expect(page).toHaveURL(/\/acceso\?motivo=401$/);
  expect(await page.evaluate(() => sessionStorage.length)).toBe(0);
});
