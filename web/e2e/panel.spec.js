import { test, expect } from '@playwright/test';
import { ID } from '../src/test/fixtures.js';
import { mockApi, loginAs } from './mock-api.js';

const panel = (page) => page.getByRole('complementary', { name: 'Detalle del elemento seleccionado' });

test.beforeEach(async ({ page }) => {
  await mockApi(page);
  await loginAs(page);
});

test('deep link a una obra: el panel compacto muestra su detalle', async ({ page }) => {
  await page.goto(`/?sel=obra:${ID.obA}`);
  const p = panel(page);
  await expect(p).toBeVisible();
  await expect(p.getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
  await expect(p.getByText('Pública')).toBeVisible();
  await expect(p.getByRole('button', { name: 'Recorrido Norte' }).first()).toBeVisible();
  await expect(p.getByRole('link', { name: 'Ana Lúcar' })).toHaveAttribute('href', `/artistas/${ID.arA}`);
  await expect(p.getByRole('link', { name: 'Bruno Mayo' })).toBeVisible();
  expect((await p.boundingBox()).width).toBeCloseTo(380, 0);
});

test('Ver detalle completo agrega x=1 por replaceState: el historial no cambia', async ({ page }) => {
  await page.goto(`/?sel=obra:${ID.obA}`);
  await expect(panel(page)).toBeVisible();
  const before = await page.evaluate(() => history.length);
  await page.getByRole('button', { name: 'Ver detalle completo' }).click();
  await expect(page).toHaveURL(/[?&]x=1/);
  expect(await page.evaluate(() => history.length)).toBe(before);
  const vp = page.viewportSize().width;
  // el ancho transiciona 320 ms: se espera a que llegue al 62 %
  await expect.poll(async () => (await panel(page).boundingBox()).width).toBeGreaterThan(vp * 0.6);
});

test('el panel va antes del área del mapa en el DOM', async ({ page }) => {
  await page.goto(`/?sel=obra:${ID.obA}`);
  await expect(panel(page)).toBeVisible();
  const first = await page.evaluate(() => {
    const a = document.querySelector('aside.panel');
    const map = document.querySelector('.mapwrap');
    return !!(a.compareDocumentPosition(map) & Node.DOCUMENT_POSITION_FOLLOWING);
  });
  expect(first).toBe(true);
});
