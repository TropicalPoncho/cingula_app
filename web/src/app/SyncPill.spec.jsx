import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import SyncPill from './SyncPill.jsx';
import { load, resetStore } from '../data/store.js';
import { makeRows, makePages } from '../test/fixtures.js';

beforeEach(() => {
  resetStore();
  sessionStorage.setItem('cingula.key', 'K');
});
afterEach(() => {
  resetStore(); // cancela el reintento automático que deja un pull fallido
  vi.unstubAllGlobals();
});

const failing = () => vi.stubGlobal('fetch', vi.fn(async () => ({ ok: false, status: 500, text: async () => '{"error":"boom"}' })));

describe('SyncPill', () => {
  it('pill con aria-haspopup/aria-expanded; abre un diálogo no modal; Esc cierra y devuelve el foco', async () => {
    const user = userEvent.setup();
    render(<SyncPill />);
    const pill = screen.getByRole('button', { name: /Leyendo/ });
    expect(pill).toHaveAttribute('aria-haspopup', 'dialog');
    expect(pill).toHaveAttribute('aria-expanded', 'false');

    await user.click(pill);
    const dialog = screen.getByRole('dialog', { name: 'Detalle del estado de sync' });
    expect(dialog).not.toHaveAttribute('aria-modal');
    expect(pill).toHaveAttribute('aria-expanded', 'true');

    await user.click(screen.getByRole('button', { name: 'Actualizar datos' })); // deshabilitado mientras lee: no cierra
    await user.keyboard('{Escape}');
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(pill).toHaveAttribute('aria-expanded', 'false');
    expect(pill).toHaveFocus();
  });

  it('clic afuera cierra el popover', async () => {
    const user = userEvent.setup();
    render(<><SyncPill /><p>afuera</p></>);
    await user.click(screen.getByRole('button', { name: /Leyendo/ }));
    await user.click(screen.getByText('afuera'));
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  it('role=alert sólo cuando aparece un error nuevo: un re-render posterior no lo repite', async () => {
    const user = userEvent.setup();
    render(<SyncPill />);
    await user.click(screen.getByRole('button', { name: /Leyendo/ }));
    expect(screen.queryByRole('alert')).toBeNull();

    failing();
    await act(() => load());
    const alert = screen.getByRole('alert');
    expect(alert).toHaveTextContent('→ 500 boom (página 1)');
    expect(alert).not.toHaveTextContent(/Bearer/);
    expect(screen.getByRole('button', { name: 'Reintentar lectura' })).toBeEnabled();
    expect(screen.getByText('Próximo reintento automático en 30 s.')).toBeVisible();

    act(() => { window.dispatchEvent(new Event('offline')); }); // re-render sin error nuevo
    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.getByText(/→ 500 boom/)).toBeInTheDocument(); // el error sigue a la vista
  });

  it('error con el popover cerrado: la pill igual lo dice', async () => {
    failing();
    render(<SyncPill />);
    await act(() => load());
    expect(screen.getByRole('button', { name: /Error de pull · sin datos/ })).toBeInTheDocument();
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  it('con datos: estado Al día, y sin conexión el botón queda deshabilitado', async () => {
    const pages = makePages(makeRows(), 1000);
    vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, status: 200, text: async () => JSON.stringify(pages[0]) })));
    const user = userEvent.setup();
    render(<SyncPill />);
    await act(() => load());
    await user.click(screen.getByRole('button', { name: /Sync al día/ }));
    expect(screen.getByText('Sin errores')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Actualizar datos' })).toBeEnabled();

    act(() => { window.dispatchEvent(new Event('offline')); });
    expect(screen.getByRole('button', { name: /Sin conexión/ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Actualizar datos' })).toBeDisabled();
    act(() => { window.dispatchEvent(new Event('online')); });
  });
});
