import { test, expect } from '@playwright/test';

// Red mockeada: ninguna request sale a un servidor real.
const GOOD = 'clave-buena';
async function mockState(page, { abort = false } = {}) {
  // Tras entrar, el shell lee el servidor: pull vacío para que ninguna request salga a la red real.
  await page.route('**/sync/pull**', (route) =>
    route.fulfill({ json: { changes: [], nextCursor: '0', hasMore: false } }),
  );
  await page.route('**/sync/state', (route) => {
    if (abort) return route.abort();
    const auth = route.request().headers()['authorization'];
    if (auth === `Bearer ${GOOD}`) {
      return route.fulfill({ json: { serverCursor: '0', lastSyncAt: null } });
    }
    return route.fulfill({ status: 401, json: { error: 'invalid or missing API key' } });
  });
}

const login = async (page, key) => {
  await page.getByLabel('API key').fill(key);
  await page.getByRole('button', { name: 'Entrar a la web' }).click();
};

test('sin clave, / redirige a /acceso', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveURL(/\/acceso$/);
  await expect(page.getByRole('heading', { name: 'Ingresá la clave de acceso' })).toBeVisible();
});

test('clave mala -> Clave rechazada', async ({ page }) => {
  await mockState(page);
  await page.goto('/acceso');
  await login(page, 'mala');
  const alert = page.getByRole('alert');
  await expect(alert).toContainText('Clave rechazada');
  await expect(alert).toContainText('El servidor respondió 401');
  await expect(page).toHaveURL(/\/acceso$/);
  expect(await page.evaluate(() => sessionStorage.getItem('cingula.key'))).toBeNull();
});

test('red caída -> Sin conexión', async ({ page }) => {
  await mockState(page, { abort: true });
  await page.goto('/acceso');
  await login(page, GOOD);
  await expect(page.getByRole('alert')).toContainText('Sin conexión');
});

test('clave buena entra al shell y la sesión sobrevive al reload', async ({ page }) => {
  await mockState(page);
  await page.goto('/acceso');
  await login(page, GOOD);
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole('button', { name: 'Salir de la web' })).toBeVisible();
  expect(await page.evaluate(() => sessionStorage.getItem('cingula.key'))).toBe(GOOD);
  expect(page.url()).not.toContain(GOOD);
  await page.reload();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole('button', { name: 'Salir de la web' })).toBeVisible();
});

test('Salir de la web borra la clave y vuelve a /acceso', async ({ page }) => {
  await mockState(page);
  await page.goto('/acceso');
  await login(page, GOOD);
  await page.getByRole('button', { name: 'Salir de la web' }).click();
  await expect(page).toHaveURL(/\/acceso$/);
  expect(await page.evaluate(() => sessionStorage.length)).toBe(0);
});

test('/acceso?motivo=401 muestra el copy de sesión vencida', async ({ page }) => {
  await page.goto('/acceso?motivo=401');
  const alert = page.getByRole('alert');
  await expect(alert).toContainText('Clave rechazada');
  await expect(alert).toContainText('La clave dejó de ser válida. Ingresala de nuevo.');
});

test('clave vacía no dispara ninguna request', async ({ page }) => {
  let hits = 0;
  await page.route('**/sync/state', (route) => {
    hits++;
    return route.abort();
  });
  await page.goto('/acceso');
  await page.getByLabel('API key').fill('   ');
  await page.getByRole('button', { name: 'Entrar a la web' }).click();
  await page.waitForTimeout(200);
  expect(hits).toBe(0);
});
