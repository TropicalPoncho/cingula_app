import { test, expect } from '@playwright/test';
import { ID, LONG_NAME, makeRows } from '../src/test/fixtures.js';
import { mockApi, loginAs } from './mock-api.js';

const list = (page) => page.getByRole('list', { name: 'Listado de obras' });
const detail = (page) => page.getByRole('region', { name: 'Detalle' });

test.beforeEach(async ({ page }) => {
  await mockApi(page);
  await loginAs(page);
});

test('la nav del header lleva a Obras y marca la sección activa', async ({ page }) => {
  await page.goto('/');
  const nav = page.getByRole('navigation', { name: 'Secciones' });
  await expect(nav.getByRole('link', { name: 'Mapa' })).toHaveAttribute('aria-current', 'page');
  await nav.getByRole('link', { name: 'Obras' }).click();
  await expect(page).toHaveURL(/\/obras$/);
  await expect(nav.getByRole('link', { name: 'Obras' })).toHaveAttribute('aria-current', 'page');
  await expect(nav.getByRole('link', { name: 'Mapa' })).not.toHaveAttribute('aria-current');
  await expect(page.getByText('3 obras')).toBeVisible();
  // subrayado mint de 2 px en la activa
  const border = await nav.getByRole('link', { name: 'Obras' }).evaluate((e) => getComputedStyle(e).borderBottomWidth);
  expect(border).toBe('2px');
});

test('filtrar por Borrador deja sólo la obra B', async ({ page }) => {
  await page.goto('/obras');
  await expect(page.getByText('3 obras')).toBeVisible();
  await page.getByLabel('Visibilidad').selectOption('draft');
  await expect(page.getByText('1 obra', { exact: true })).toBeVisible();
  await expect(list(page).getByRole('listitem')).toHaveCount(1);
  await expect(list(page).getByRole('link', { name: new RegExp(LONG_NAME.slice(0, 20)) })).toBeVisible();
  expect(new URL(page.url()).searchParams.get('vis')).toBe('draft');
});

test('abrir la obra A muestra su detalle completo y conserva los filtros', async ({ page }) => {
  await page.goto('/obras?rec=' + ID.rec1);
  await list(page).getByRole('link', { name: /Obra Aurora/ }).click();
  await expect(page).toHaveURL(new RegExp(`/obras/${ID.obA}\\?rec=${ID.rec1}$`));
  const d = detail(page);
  await expect(d.getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
  await expect(d.getByRole('navigation', { name: 'Ruta' })).toContainText('Obras');
  await expect(d.getByRole('link', { name: 'Obras', exact: true })).toBeVisible();
  await expect(d.getByText('Ruta A')).toBeVisible();
});

test('deep link /obras/<uuid A> carga directo', async ({ page }) => {
  await page.goto(`/obras/${ID.obA}`);
  await expect(detail(page).getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
  await expect(detail(page).getByRole('link', { name: 'Ana Lúcar' })).toHaveAttribute('href', `/artistas/${ID.arA}`);
});

test('Artistas: listado, detalle con APARECE EN enlazado a la obra y sin usuario', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('navigation', { name: 'Secciones' }).getByRole('link', { name: 'Artistas' }).click();
  await expect(page).toHaveURL(/\/artistas$/);
  await expect(page.getByText('2 artistas')).toBeVisible();
  await page.getByRole('list', { name: 'Listado de artistas' }).getByRole('link', { name: /Bruno Mayo/ }).click();
  await expect(page).toHaveURL(new RegExp(`/artistas/${ID.arB}$`));
  const d = detail(page);
  await expect(d.getByText('ARTISTA', { exact: true })).toBeVisible();
  await expect(d.getByRole('heading', { name: 'Bruno Mayo' })).toBeVisible();
  await expect(d.getByText('APARECE EN', { exact: true })).toBeVisible();
  await expect(page.getByText('user-secreto')).toHaveCount(0);
  await d.getByRole('link', { name: /Obra Aurora/ }).click();
  await expect(page).toHaveURL(new RegExp(`/obras/${ID.obA}$`));
  await expect(detail(page).getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
});

test('Artistas vacío: copy fijo cuando el servidor no tiene artistas', async ({ page }) => {
  const rows = makeRows().filter((r) => r.table !== 'artistas' && r.table !== 'obra_artistas');
  await mockApi(page, { rows }); // se registra después del beforeEach: el último route gana
  await page.goto('/artistas');
  await expect(page.getByText('Todavía no hay artistas en el servidor.')).toBeVisible();
});

test('uuid inexistente: No encontramos esta obra + Volver al listado', async ({ page }) => {
  await page.goto('/obras/no-existe');
  await expect(page.getByText('No encontramos esta obra.')).toBeVisible();
  await page.getByRole('link', { name: 'Volver al listado' }).click();
  await expect(page).toHaveURL(/\/obras$/);
});

test('< 900 px el detalle reemplaza al listado y Volver al listado lo devuelve [OI-05]', async ({ page }) => {
  await page.setViewportSize({ width: 800, height: 900 });
  await page.goto('/obras');
  await expect(list(page)).toBeVisible();
  await expect(detail(page)).toBeHidden();
  await list(page).getByRole('link', { name: /Obra Aurora/ }).click();
  await expect(detail(page).getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
  await expect(list(page)).toBeHidden();
  await detail(page).getByRole('link', { name: 'Volver al listado' }).click();
  await expect(list(page)).toBeVisible();
});

test('nombre de 60 caracteres: la fila no crece y el detalle no desborda', async ({ page }) => {
  await page.goto(`/obras/${ID.obB}`);
  const row = list(page).getByRole('link', { name: new RegExp(LONG_NAME.slice(0, 20)) });
  expect((await row.boundingBox()).height).toBeCloseTo(64, 0);
  expect(await detail(page).evaluate((e) => e.scrollWidth <= e.clientWidth)).toBe(true);
});

const mini = (page) => detail(page).getByRole('img', { name: /^Mapa de / });

test('mini-mapa: 240 px, role=img con aria-label, atribución OSM, sin zoom y sin elementos focuseables', async ({ page }) => {
  await page.goto(`/obras/${ID.obA}`);
  await expect(mini(page)).toHaveAttribute('aria-label', 'Mapa de Obra Aurora');
  await expect(detail(page).getByRole('link', { name: '© OpenStreetMap contributors' })).toBeVisible();
  const box = detail(page).locator('.minimap');
  await expect(box.locator('path.cg-cover').first()).toBeVisible();
  expect((await box.boundingBox()).height).toBeCloseTo(242, -1); // 240 + borde
  await expect(box.locator('.leaflet-control-zoom')).toHaveCount(0);
  await expect(box.locator('[tabindex], .leaflet-interactive')).toHaveCount(0);
});

test('mini-mapa: ni la rueda ni el arrastre ni Tab lo mueven o lo enfocan', async ({ page }) => {
  await page.goto(`/obras/${ID.obA}`);
  const cover = detail(page).locator('.minimap path.cg-cover').first();
  await expect(cover).toBeVisible();
  const before = await cover.boundingBox();
  const b = await detail(page).locator('.minimap').boundingBox();
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2);
  await page.mouse.wheel(0, -600);
  await page.mouse.down();
  await page.mouse.move(b.x + b.width / 2 + 80, b.y + b.height / 2 + 40, { steps: 4 });
  await page.mouse.up();
  await page.waitForTimeout(400);
  const after = await cover.boundingBox();
  expect(Math.abs(after.x - before.x) + Math.abs(after.y - before.y) + Math.abs(after.width - before.width)).toBeLessThan(2);
  // Tab recorre toda la página sin caer nunca dentro del mapa
  for (let i = 0; i < 60; i++) {
    await page.keyboard.press('Tab');
    expect(await page.evaluate(() => !!document.activeElement?.closest('.mapview'))).toBe(false);
  }
});

test('abrir un path desde el detalle: breadcrumb Obras / Obra / Path y Volver a {Obra} vuelve sin salir de la página', async ({ page }) => {
  await page.goto(`/obras/${ID.obA}`);
  const d = detail(page);
  await d.getByRole('button', { name: /Ruta A/ }).first().click();
  expect(new URL(page.url()).pathname).toBe(`/obras/${ID.obA}`);
  expect(new URL(page.url()).searchParams.get('sel')).toBe(`path:${ID.pathA}`);
  await expect(d.getByRole('navigation', { name: 'Ruta' })).toHaveText('Obras/Obra Aurora/Ruta A');
  await expect(d.getByRole('heading', { name: 'Ruta A' })).toBeVisible();
  await expect(mini(page)).toBeVisible(); // el mini-mapa sigue y resalta la selección
  await d.getByRole('button', { name: 'Volver a Obra Aurora' }).click();
  await expect(d.getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
  expect(new URL(page.url()).searchParams.has('sel')).toBe(false);
});
