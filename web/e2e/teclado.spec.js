import { test, expect } from '@playwright/test';
import { ID } from '../src/test/fixtures.js';
import { mockApi, loginAs } from './mock-api.js';

// R9: el mapa se opera entero con teclado. Tiles y red mockeados (mock-api.js).
const panel = (page) => page.getByRole('complementary', { name: 'Detalle del elemento seleccionado' });
const covers = (page) => page.locator('path.cg-cover');
const label = (page) => page.evaluate(() => document.activeElement?.getAttribute('aria-label') ?? null);

// Tab hasta que el foco cae en un elemento cuyo aria-label cumple `re`; falla si no llega en `max` pasos.
async function tabTo(page, re, max = 80) {
  for (let i = 0; i < max; i++) {
    await page.keyboard.press('Tab');
    const l = await label(page);
    if (l && re.test(l)) return l;
  }
  throw new Error(`Tab no llegó a ${re} en ${max} pasos`);
}

test.beforeEach(async ({ page }) => {
  await mockApi(page);
  await loginAs(page);
});

test('Tab llega al portal de la obra A y Enter abre su panel', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await tabTo(page, /^Portal Portal A, radio 15 m$/);
  await page.keyboard.press('Enter');
  await expect(panel(page).getByRole('heading', { name: 'Portal A' })).toBeVisible();
});

test('modo Círculos: un tab stop por path y las flechas recorren los 32 triggers en orden', async ({ page }) => {
  await page.goto(`/?modo=circ&sel=trigger:${ID.trA(0)}`);
  const circles = page.getByRole('button', { name: /^Trigger \d+ de \d+, radio/ });
  await expect(circles).toHaveCount(35); // path A (32) + path B (3), todos dentro del viewport
  // Roving tabindex: exactamente un tab stop por path (A y B).
  await expect(page.locator('[aria-label^="Trigger "][tabindex="0"]')).toHaveCount(2);
  await expect(page.getByRole('heading', { name: 'Trigger 001' })).toBeVisible();

  await tabTo(page, /^Trigger 1 de 32, radio 12 m$/); // el activo (seleccionado) del path A
  await page.keyboard.press('ArrowRight');
  await expect(panel(page).getByRole('heading', { name: 'Trigger 002' })).toBeVisible();
  await expect(panel(page).getByText('2 de 32')).toBeVisible();
  expect(await label(page)).toBe('Trigger 2 de 32, radio 12 m');
  expect(new URL(page.url()).searchParams.get('sel')).toBe(`trigger:${ID.trA(1)}`);
  await expect(page.locator('[aria-label^="Trigger "][tabindex="0"]')).toHaveCount(2); // el tab stop viajó, no se duplicó

  // Recorrer todo el path con las flechas: orden de position, sin saltos.
  for (let n = 3; n <= 32; n++) {
    await page.keyboard.press('ArrowDown');
    await expect(panel(page).getByText(`${n} de 32`)).toBeVisible();
    expect(await label(page)).toBe(`Trigger ${n} de 32, radio 12 m`);
  }
  await page.keyboard.press('ArrowRight'); // extremo: no hace nada
  expect(await label(page)).toBe('Trigger 32 de 32, radio 12 m');
  await page.keyboard.press('ArrowLeft');
  await expect(panel(page).getByText('31 de 32')).toBeVisible();
  await page.keyboard.press('ArrowUp');
  expect(await label(page)).toBe('Trigger 30 de 32, radio 12 m');

  // Sin trampa de foco: Tab sale del path (los otros 31 círculos tienen tabindex -1).
  await page.keyboard.press('Tab');
  expect(await label(page)).not.toMatch(/ de 32, radio/);
});

test('Esc: expandido -> compacto -> cerrado, y el foco vuelve a la obra que abrió el panel', async ({ page }) => {
  await page.goto('/');
  await expect(covers(page)).toHaveCount(2);
  await page.getByRole('button', { name: 'Obra Obra Aurora', exact: true }).focus();
  await page.keyboard.press('Enter');
  await expect(panel(page).getByRole('heading', { name: 'Obra Aurora' })).toBeVisible();

  await page.getByRole('button', { name: 'Ver detalle completo' }).click(); // el foco pasa al panel
  await page.keyboard.press('Escape');
  await expect(page.getByRole('button', { name: 'Ver detalle completo' })).toBeVisible(); // compacto
  await page.keyboard.press('Escape');
  await expect(panel(page)).toHaveCount(0);
  expect(await label(page)).toBe('Obra Obra Aurora');
});

test('cerrar el panel de un trigger devuelve el foco al círculo que lo abrió', async ({ page }) => {
  await page.goto(`/?modo=circ&sel=trigger:${ID.trA(0)}`);
  await tabTo(page, /^Trigger 1 de 32, radio 12 m$/);
  await page.keyboard.press('ArrowRight');
  await expect(panel(page).getByText('2 de 32')).toBeVisible();
  await page.getByRole('button', { name: 'Cerrar panel' }).click();
  await expect(panel(page)).toHaveCount(0);
  expect(await label(page)).toBe('Trigger 2 de 32, radio 12 m');
  await expect(page.getByRole('button', { name: /^Trigger 2 de 32/ })).toHaveCount(1); // el círculo sigue ahí
});
