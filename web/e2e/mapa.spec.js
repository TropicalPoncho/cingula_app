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

const recSelect = (page) => page.getByRole('combobox', { name: 'Recorrido' });
const legend = (page) => page.locator('.legend');

test('elegir un recorrido filtra y abre su panel con créditos; Todos lo cierra', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await expect(legend(page)).toContainText('3 obras'); // A, B y C (sin cobertura: cuenta pero no se dibuja)
  await expect(recSelect(page).locator('option')).toHaveText(['Todos los recorridos', 'Recorrido Norte', 'Recorrido Sur', 'Sin recorrido']);

  await recSelect(page).selectOption(ID.rec1);
  const sp = new URL(page.url()).searchParams;
  expect(sp.get('rec')).toBe(ID.rec1);
  expect(sp.get('sel')).toBe(`recorrido:${ID.rec1}`);
  await expect(panel(page).getByRole('heading', { name: 'Recorrido Norte' })).toBeVisible();
  await expect(panel(page).getByText('Créditos', { exact: true })).toBeVisible();
  await expect(legend(page)).toContainText('2 obras');

  await recSelect(page).selectOption('');
  await expect(panel(page)).toHaveCount(0);
  expect(new URL(page.url()).searchParams.get('rec')).toBeNull();
  await expect(legend(page)).toContainText('3 obras');
});

test('Sin recorrido: leyenda de 1 obra (C, sin cobertura) y ningún rectángulo, sin panel', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await recSelect(page).selectOption('none');
  await expect(legend(page)).toContainText('1 obra ');
  await expect(covers(page)).toHaveCount(0);
  await expect(panel(page)).toHaveCount(0);
});

test('elegir una obra del recorrido filtrado no cambia el filtro; un rec desconocido se ignora', async ({ page }) => {
  await page.goto(`/?rec=${ID.rec1}`);
  await expect(covers(page)).toHaveCount(2);
  await page.getByRole('button', { name: 'Obra Obra Aurora' }).dispatchEvent('click');
  await expect(panel(page).getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
  expect(new URL(page.url()).searchParams.get('rec')).toBe(ID.rec1);

  await page.goto('/?rec=no-existe');
  await expect(covers(page)).toHaveCount(2);
  await expect(recSelect(page)).toHaveValue('');
  await expect(legend(page)).toContainText('3 obras');
});

test('apagar Cobertura quita rectángulos y etiquetas; volver a prenderla los trae de vuelta', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  const chk = page.getByRole('checkbox', { name: 'Cobertura' });
  await chk.uncheck();
  await expect(covers(page)).toHaveCount(0);
  await expect(page.locator('.obra-label')).toHaveCount(0);
  await expect(page.locator('path[stroke-dasharray="4 4"]')).toHaveCount(1); // Paths sigue prendida
  await chk.check();
  await expect(covers(page)).toHaveCount(2);
  await page.getByRole('checkbox', { name: 'Paths' }).uncheck();
  await expect(page.locator('path[stroke-dasharray="4 4"]')).toHaveCount(0);
});

test('sin obras en el servidor: velo vacío y el selector sólo ofrece Todos', async ({ page }) => {
  await mockApi(page, { rows: [] });
  await page.goto('/');
  await expect(page.getByText('Todavía no hay obras en el servidor.')).toBeVisible();
  await expect(page.getByText('Cuando el celular sincronice la primera obra, va a aparecer acá.')).toBeVisible();
  await expect(recSelect(page).locator('option')).toHaveText(['Todos los recorridos']);
  await expect(covers(page)).toHaveCount(0);
});

test('primer pull fallido: error central con Reintentar lectura, y el selector queda deshabilitado', async ({ page }) => {
  await mockApi(page, { failPage: 1, failTimes: 99 });
  await page.goto('/');
  await expect(page.getByText('No se pudo leer el servidor.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Reintentar lectura' })).toBeVisible();
  await expect(recSelect(page)).toBeDisabled();
});

test('la mapbar envuelve a 1000 px y el mapa conserva el resto del ancho [asunción OI-05]', async ({ page }) => {
  await page.setViewportSize({ width: 1000, height: 700 });
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  const bar = await page.locator('.mapbar').boundingBox();
  const view = await page.locator('.mapview').boundingBox();
  expect(bar.x + bar.width).toBeLessThanOrEqual(view.x + view.width);
  expect(view.width).toBeGreaterThan(500);
});
