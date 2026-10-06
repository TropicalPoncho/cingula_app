import { test, expect } from '@playwright/test';
import { ID } from '../src/test/fixtures.js';
import { mockApi, loginAs } from './mock-api.js';

const panel = (page) => page.getByRole('complementary', { name: 'Detalle del elemento seleccionado' });
const covers = (page) => page.locator('path.cg-cover');

test.beforeEach(async ({ page }) => {
  await mockApi(page);
  await loginAs(page);
});

test('dibuja una cobertura por obra con cobertura (C sin cobertura y D borrada no) y atribuye a OSM', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await expect(page.getByRole('link', { name: '© OpenStreetMap contributors' })).toBeVisible();
});

test('auto-encuadre: las coberturas quedan dentro del mapa, con el padding de 70 px', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  const view = await page.locator('.mapview').boundingBox();
  await expect.poll(async () => {
    const b = await covers(page).first().boundingBox();
    return b.x >= view.x + 60 && b.y >= view.y + 60 && b.x + b.width <= view.x + view.width - 60 && b.y + b.height <= view.y + view.height - 60;
  }).toBe(true);
});

test('clic en una cobertura abre el panel de la obra; expandir no rompe el mapa', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  // Las fixtures A y B tienen el mismo bbox (B encima): el clic se despacha sobre el nodo de A.
  await page.getByRole('button', { name: 'Obra Obra Aurora' }).dispatchEvent('click');
  await expect(panel(page).getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
  expect(new URL(page.url()).searchParams.get('sel')).toBe(`obra:${ID.obA}`);

  await page.getByRole('button', { name: 'Ver detalle completo' }).click();
  const vp = page.viewportSize().width;
  await expect.poll(async () => (await panel(page).boundingBox()).width).toBeGreaterThan(vp * 0.6);
  await expect(covers(page)).toHaveCount(2);
  const box = await page.locator('.mapview').boundingBox();
  expect(box.width).toBeGreaterThan(0);
});

test('capas: corredor por tramo, un hueco ámbar punteado y etiquetas de obra', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await expect(page.locator('path[stroke-dasharray="4 4"]')).toHaveCount(1); // el hueco de la ruta A
  await expect(page.locator('.obra-label')).toHaveCount(2);
  await expect(page.locator('.obra-label span', { hasText: 'Obra Aurora' })).toBeVisible();
});

test('teclado: Enter abre el panel de una obra, de un path y de un portal', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  for (const [name, heading] of [
    ['Obra Obra Aurora', 'Obra Aurora'],
    ['Path Ruta A', 'Ruta A'],
    ['Portal Portal A, radio 15 m', 'Portal A'],
  ]) {
    await page.getByRole('button', { name, exact: true }).focus();
    await page.keyboard.press('Enter');
    await expect(panel(page).getByRole('heading', { name: heading })).toBeVisible();
  }
});

test('foco visible sobre una cobertura: trazo de 3,5 px', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await page.keyboard.press('Shift'); // última interacción por teclado: el foco programático cuenta como :focus-visible
  await page.getByRole('button', { name: 'Obra Obra Aurora', exact: true }).focus();
  const sw = await page.locator(':focus').evaluate((e) => getComputedStyle(e).strokeWidth);
  expect(parseFloat(sw)).toBeCloseTo(3.5, 1);
});
