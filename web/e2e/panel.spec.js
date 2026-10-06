import { test, expect } from '@playwright/test';
import { ID, LONG_NAME } from '../src/test/fixtures.js';
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

test('plegar deja el riel de 48 px; Abrir panel lo reabre; Esc cierra y limpia la URL', async ({ page }) => {
  await page.goto(`/?sel=obra:${ID.obA}`);
  await page.getByRole('button', { name: 'Plegar panel' }).click();
  await expect.poll(async () => (await panel(page).boundingBox()).width).toBeCloseTo(48, 0);
  await expect(panel(page).getByText('OBRA · Obra Aurora')).toBeVisible();
  await page.getByRole('button', { name: 'Abrir panel' }).click();
  await expect(page.getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(panel(page)).toHaveCount(0);
  expect(new URL(page.url()).search).toBe('');
});

test('selección inexistente: aviso y Cerrar aviso', async ({ page }) => {
  await page.goto('/?sel=obra:no-existe');
  await expect(page.getByText('Este elemento ya no existe en el servidor.')).toBeVisible();
  await page.getByRole('button', { name: 'Cerrar aviso' }).click();
  await expect(panel(page)).toHaveCount(0);
});

test('nombre de 60 caracteres: título en 2 líneas como máximo y sin desborde horizontal', async ({ page }) => {
  await page.goto(`/?sel=obra:${ID.obB}`);
  const title = page.getByRole('heading', { name: LONG_NAME });
  await expect(title).toBeVisible();
  const lh = await title.evaluate((e) => parseFloat(getComputedStyle(e).lineHeight));
  expect((await title.boundingBox()).height).toBeLessThanOrEqual(lh * 2 + 1);
  expect(await panel(page).evaluate((e) => e.scrollWidth <= e.clientWidth)).toBe(true);
  await page.getByRole('button', { name: 'Plegar panel' }).click();
  const vt = panel(page).locator('.vt');
  await expect(vt).toBeVisible();
  expect((await vt.boundingBox()).height).toBeLessThanOrEqual(420);
});

test('deep link a un path de 32 triggers: facts, huecos y camino de vuelta a la obra', async ({ page }) => {
  await page.goto(`/?sel=path:${ID.pathA}`);
  const p = panel(page);
  await expect(p.getByRole('heading', { name: 'Ruta A' })).toBeVisible();
  await expect(p.getByText('32 · radio 12 m · cada ≈ 10 m')).toBeVisible();
  await expect(p.getByText('1 hueco')).toBeVisible();
  await p.getByRole('button', { name: /Volver a Obra Aurora/ }).click();
  await expect(p.getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
  expect(new URL(page.url()).searchParams.get('sel')).toBe(`obra:${ID.obA}`);
});

test('< 900 px el panel es una hoja inferior de 55 % [asunción OI-05]', async ({ page }) => {
  await page.setViewportSize({ width: 800, height: 700 });
  await page.goto(`/?sel=obra:${ID.obA}`);
  await expect(panel(page)).toBeVisible();
  await expect.poll(async () => Math.round((await panel(page).boundingBox()).width)).toBe(800);
  const box = await panel(page).boundingBox();
  expect(box.height).toBeCloseTo(700 * 0.55, 0);
  expect(box.y + box.height).toBeCloseTo(700, 0);
});
