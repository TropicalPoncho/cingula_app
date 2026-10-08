import { test, expect } from '@playwright/test';
import { ID, LONG_NAME, makeRows } from '../src/test/fixtures.js';
import { mockApi, loginAs } from './mock-api.js';

const panel = (page) => page.getByRole('complementary', { name: 'Detalle del elemento seleccionado' });
const covers = (page) => page.locator('path.cg-cover');

// D-22: los filtros viven en una tarjeta no modal; el helper la abre sólo si hace falta (un clic afuera la cierra).
const menuBtn = (page) => page.getByRole('button', { name: 'Capas y filtros' });
async function menu(page) {
  if ((await menuBtn(page).getAttribute('aria-expanded')) === 'false') await menuBtn(page).click();
  return page.getByRole('dialog', { name: 'Capas y filtros' });
}
const recSelect = async (page) => (await menu(page)).getByRole('combobox', { name: 'Recorrido' });
const modeBtn = async (page, name) => (await menu(page)).getByRole('button', { name });
const chip = (page) => page.locator('.mchip-t');
const quitar = (page) => page.getByRole('button', { name: 'Quitar filtro de recorrido' });

test.beforeEach(async ({ page }) => {
  await mockApi(page);
  await loginAs(page);
});

test('dibuja un contorno por obra con triggers (C sin triggers y D borrada no) y atribuye a OSM', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await expect(page.getByRole('link', { name: '© OpenStreetMap contributors' })).toBeVisible();
});

test('contorno = unión: A son 3 subtrazos (2 tramos + portal), B uno (ni un rectángulo ni 33 círculos sueltos)', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  const subpaths = async (name) => ((await page.locator('path.cg-cover').and(page.getByLabel(name, { exact: true })).getAttribute('d')).match(/M/g) ?? []).length;
  expect(await subpaths('Obra Obra Aurora')).toBe(3);
  expect(await subpaths(`Obra ${LONG_NAME}`)).toBe(1);
});

test('auto-encuadre: los contornos quedan dentro del mapa, con el padding de 70 px', async ({ page }) => {
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

test('capas: corredor por tramo y un hueco ámbar punteado', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await expect(page.locator('path[stroke-dasharray="4 4"]')).toHaveCount(1); // el hueco de la ruta A
});

test('etiquetas por zoom: de cerca paths, de lejos obras, nunca juntas; sin puntero, sin lector y sin tab stops', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  // Encuadre inicial (zoom alto): paths y portal, ninguna obra.
  await expect(page.locator('.path-label span', { hasText: 'Ruta A' })).toBeVisible();
  await expect(page.locator('.obra-label')).toHaveCount(0);

  const out = page.getByRole('button', { name: 'Zoom out' });
  for (let i = 0; i < 6 && (await page.locator('.obra-label').count()) === 0; i++) {
    expect(await page.locator('.obra-label').count() * await page.locator('.path-label').count()).toBe(0);
    await out.click();
    await page.waitForTimeout(400); // Leaflet ignora el siguiente clic mientras anima el zoom
  }
  await expect(page.locator('.obra-label span').first()).toBeVisible();
  await expect(page.locator('.path-label')).toHaveCount(0);
  await expect(page.locator('.portal-label')).toHaveCount(0);
  await expect(page.locator('.obra-label span', { hasText: 'Obra Aurora' })).toBeVisible();

  // Accesibilidad: ninguna etiqueta captura el puntero, se anuncia ni es focuseable.
  const span = page.locator('.map-label span').first();
  expect(await span.evaluate((e) => getComputedStyle(e).pointerEvents)).toBe('none');
  await expect(span).toHaveAttribute('aria-hidden', 'true');
  await expect(page.locator('.map-label[tabindex], .map-label [tabindex]')).toHaveCount(0);
});

test('etiqueta larga recortada: 200 px de ancho máximo con elipsis', async ({ page }) => {
  const rows = makeRows();
  rows.find((r) => r.payload.uuid === ID.pathA).payload.name = LONG_NAME;
  await page.unrouteAll();
  await mockApi(page, { rows });
  await page.goto('/');
  const span = page.locator('.path-label span', { hasText: LONG_NAME.slice(0, 20) });
  await expect(span).toBeVisible();
  const m = await span.evaluate((e) => ({ w: e.getBoundingClientRect().width, ov: getComputedStyle(e).textOverflow, sw: e.scrollWidth, cw: e.clientWidth }));
  expect(m.w).toBeLessThanOrEqual(200.5);
  expect(m.ov).toBe('ellipsis');
  expect(m.sw).toBeGreaterThan(m.cw); // el texto está de verdad recortado
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

const legend = (page) => page.locator('.legend');

test('elegir un recorrido filtra y abre su panel con créditos; Todos lo cierra', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await expect(legend(page)).toContainText('3 obras'); // A, B y C (sin cobertura: cuenta pero no se dibuja)
  await expect((await recSelect(page)).locator('option')).toHaveText(['Todos los recorridos', 'Recorrido Norte', 'Recorrido Sur', 'Sin recorrido']);
  await expect(chip(page)).toHaveCount(0);

  await (await recSelect(page)).selectOption(ID.rec1);
  const sp = new URL(page.url()).searchParams;
  expect(sp.get('rec')).toBe(ID.rec1);
  expect(sp.get('sel')).toBe(`recorrido:${ID.rec1}`);
  await expect(panel(page).getByRole('heading', { name: 'Recorrido Norte' })).toBeVisible();
  await expect(panel(page).getByText('Créditos', { exact: true })).toBeVisible();
  await expect(legend(page)).toContainText('2 obras');
  await expect(chip(page)).toHaveText('Recorrido Norte');

  await (await recSelect(page)).selectOption('');
  await expect(panel(page)).toHaveCount(0);
  expect(new URL(page.url()).searchParams.get('rec')).toBeNull();
  await expect(legend(page)).toContainText('3 obras');
  await expect(chip(page)).toHaveCount(0);
});

test('chip: el × equivale a Todos los recorridos (cierra el panel del recorrido) y devuelve el foco al botón', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await (await recSelect(page)).selectOption(ID.rec1);
  await expect(chip(page)).toHaveText('Recorrido Norte');
  await expect(panel(page)).toHaveCount(1);
  const x = await quitar(page).boundingBox();
  expect(x.width).toBeGreaterThanOrEqual(43.5);
  expect(x.height).toBeGreaterThanOrEqual(43.5);

  await quitar(page).click();
  await expect(chip(page)).toHaveCount(0);
  await expect(panel(page)).toHaveCount(0);
  const sp = new URL(page.url()).searchParams;
  expect(sp.get('rec')).toBeNull();
  expect(sp.get('sel')).toBeNull();
  await expect(menuBtn(page)).toBeFocused();
});

test('el enlace del recorrido (desde Obras) abre el mapa con el chip visible', async ({ page }) => {
  await page.goto(`/?rec=${ID.rec1}&sel=recorrido:${ID.rec1}`);
  await expect(covers(page)).toHaveCount(2);
  await expect(chip(page)).toHaveText('Recorrido Norte');
  await expect(panel(page).getByRole('heading', { name: 'Recorrido Norte' })).toBeVisible();
});

test('D-03: las tres capas vienen prendidas al abrir el menú, con Corredor activo', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  const d = await menu(page);
  for (const n of ['Cobertura', 'Paths', 'Portales']) await expect(d.getByRole('checkbox', { name: n })).toBeChecked();
  await expect(d.getByRole('button', { name: 'Corredor' })).toHaveAttribute('aria-pressed', 'true');
});

test('Esc dentro de la tarjeta la cierra y devuelve el foco; con el panel abierto, Esc cierra sólo la tarjeta; clic en el mapa la cierra', async ({ page }) => {
  await page.goto(`/?sel=obra:${ID.obA}`);
  await expect(panel(page).getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();
  const d = await menu(page);
  await d.getByRole('checkbox', { name: 'Cobertura' }).focus();
  await page.keyboard.press('Escape');
  await expect(d).toHaveCount(0);
  await expect(menuBtn(page)).toBeFocused();
  await expect(menuBtn(page)).toHaveAttribute('aria-expanded', 'false');
  await expect(panel(page)).toHaveCount(1); // el Esc era del menú, no del panel

  await menu(page);
  await page.locator('.mapview').click({ position: { x: 600, y: 400 } });
  await expect(page.getByRole('dialog', { name: 'Capas y filtros' })).toHaveCount(0);
});

test('teclas dentro de la tarjeta no mueven ni hacen zoom en el mapa ni cierran el panel', async ({ page }) => {
  await page.goto(`/?sel=obra:${ID.obA}`);
  await expect(covers(page)).toHaveCount(2);
  const obra = page.locator('path.cg-cover').and(page.getByLabel('Obra Obra Aurora', { exact: true }));
  await page.waitForTimeout(600); // el encuadre inicial termina
  const d = await menu(page);
  await d.getByRole('checkbox', { name: 'Cobertura' }).focus();
  const before = await obra.boundingBox();
  for (const k of ['ArrowLeft', 'ArrowUp', 'a', '+', '-']) await page.keyboard.press(k);
  await page.waitForTimeout(400);
  const after = await obra.boundingBox();
  expect(Math.abs(after.x - before.x) + Math.abs(after.y - before.y) + Math.abs(after.width - before.width) + Math.abs(after.height - before.height)).toBeLessThan(2);
  await expect(d).toBeVisible();
  await expect(panel(page)).toHaveCount(1);
});

test('tab-order real: el primer elemento enfocado dentro del mapa es "Capas y filtros"', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  let first = null;
  for (let i = 0; i < 30 && !first; i++) {
    await page.keyboard.press('Tab');
    first = await page.evaluate(() => (document.activeElement?.closest('.mapwrap') ? document.activeElement.getAttribute('aria-label') : null));
  }
  expect(first).toBe('Capas y filtros');
});

test('Sin recorrido: leyenda de 1 obra (C, sin triggers) y ningún contorno, sin panel', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await (await recSelect(page)).selectOption('none');
  await expect(chip(page)).toHaveText('Sin recorrido');
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
  await expect(chip(page)).toHaveCount(0); // un rec desconocido no muestra chip
  await expect(await recSelect(page)).toHaveValue('');
  await expect(legend(page)).toContainText('3 obras');
});

test('apagar Cobertura quita contornos; apagar Paths quita sus etiquetas; volver a prenderlas las trae de vuelta', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await expect(page.locator('.path-label')).not.toHaveCount(0);
  const chk = (await menu(page)).getByRole('checkbox', { name: 'Cobertura' });
  await chk.uncheck();
  await expect(covers(page)).toHaveCount(0);
  await expect(page.locator('path[stroke-dasharray="4 4"]')).toHaveCount(1); // Paths sigue prendida
  await chk.check();
  await expect(covers(page)).toHaveCount(2);
  await (await menu(page)).getByRole('checkbox', { name: 'Paths' }).uncheck();
  await expect(page.locator('path[stroke-dasharray="4 4"]')).toHaveCount(0);
  await expect(page.locator('.path-label')).toHaveCount(0);
});

test('sin obras en el servidor: velo vacío y el selector sólo ofrece Todos', async ({ page }) => {
  await mockApi(page, { rows: [] });
  await page.goto('/');
  await expect(page.getByText('Todavía no hay obras en el servidor.')).toBeVisible();
  await expect(page.getByText('Cuando el celular sincronice la primera obra, va a aparecer acá.')).toBeVisible();
  await expect((await recSelect(page)).locator('option')).toHaveText(['Todos los recorridos']);
  await expect(covers(page)).toHaveCount(0);
});

test('primer pull fallido: error central con Reintentar lectura, y el selector queda deshabilitado', async ({ page }) => {
  await mockApi(page, { failPage: 1, failTimes: 99 });
  await page.goto('/');
  await expect(page.getByText('No se pudo leer el servidor.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Reintentar lectura' })).toBeVisible();
  await expect(await recSelect(page)).toBeDisabled();
});

test('la tarjeta nunca tapa el panel (1280 px, también expandido) y a 800 px ocupa el ancho y termina antes de la hoja [asunción OI-05]', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto(`/?sel=obra:${ID.obA}&x=1`);
  await expect(covers(page)).toHaveCount(2);
  const card = await (await menu(page)).boundingBox();
  const pb = await panel(page).boundingBox();
  expect(card.x).toBeGreaterThanOrEqual(pb.x + pb.width - 0.5);

  await page.setViewportSize({ width: 800, height: 700 });
  await page.goto(`/?sel=obra:${ID.obA}`);
  await expect(covers(page)).toHaveCount(2);
  const small = await (await menu(page)).boundingBox();
  const sheet = await panel(page).boundingBox();
  expect(small.width).toBeGreaterThanOrEqual(800 - 16 - 2);
  expect(small.y + small.height).toBeLessThanOrEqual(sheet.y);
});

// D-17 / R6: modo Círculos (CIRCLES_MIN_ZOOM = 16 medido en 12-03).
const triggers = (page) => page.getByRole('button', { name: /^Trigger \d+ de \d+, radio/ });
const hint = (page) => page.getByText('Acercá el mapa para ver los círculos.');

test('modo Círculos: pista bajo z16, 32 círculos al encuadrar el path y clic abre el trigger', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await (await modeBtn(page, 'Círculos')).click();
  expect(new URL(page.url()).searchParams.get('modo')).toBe('circ');
  await expect(await modeBtn(page, 'Círculos')).toHaveAttribute('aria-pressed', 'true');

  // Vista general (zoom bajo): se ve el corredor y la pista, sin círculos.
  const out = page.getByRole('button', { name: 'Zoom out' });
  for (let i = 0; i < 4; i++) {
    await out.click();
    await page.waitForTimeout(400); // Leaflet ignora el siguiente clic mientras anima el zoom
  }
  await expect(hint(page)).toBeVisible();
  await expect(triggers(page)).toHaveCount(0);

  // Desde el panel: elegir el path encuadra sus triggers (fitTarget, 12-07) y entran los 32 círculos.
  await page.getByRole('button', { name: 'Obra Obra Aurora' }).dispatchEvent('click');
  await panel(page).getByRole('button', { name: /^Ruta A/ }).click();
  await expect(hint(page)).toHaveCount(0);
  await expect(triggers(page)).toHaveCount(35); // 32 del path A + 3 del path B, que cae dentro del viewport
  await expect(page.getByRole('button', { name: /^Trigger \d+ de 32, radio/ })).toHaveCount(32);
  await expect(page.locator('path[stroke-dasharray="4 4"]')).toHaveCount(1); // el hueco sigue en ámbar en este modo

  await triggers(page).nth(4).dispatchEvent('click');
  await expect(panel(page).getByRole('heading', { name: 'Trigger 005' })).toBeVisible();
  await expect(panel(page).getByText('5 de 32')).toBeVisible();
  expect(new URL(page.url()).searchParams.get('sel')).toBe(`trigger:${ID.trA(4)}`);

  // Volver a Corredor quita los círculos y el modo sale de la URL.
  await (await modeBtn(page, 'Corredor')).click();
  await expect(triggers(page)).toHaveCount(0);
  expect(new URL(page.url()).searchParams.get('modo')).toBeNull();
});

test('cambiar de modo no re-encuadra el mapa (D-02)', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  const before = await covers(page).first().boundingBox();
  await (await modeBtn(page, 'Círculos')).click();
  await (await modeBtn(page, 'Corredor')).click();
  await page.waitForTimeout(400);
  const after = await covers(page).first().boundingBox();
  expect(Math.abs(after.x - before.x) + Math.abs(after.y - before.y)).toBeLessThan(2);
});
