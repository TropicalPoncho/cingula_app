import { test, expect } from '@playwright/test';
import { ID, LONG_NAME } from '../src/test/fixtures.js';
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
