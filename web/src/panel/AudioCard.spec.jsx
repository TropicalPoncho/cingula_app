import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { applyRows, buildModel, emptyTables } from '../data/model.js';
import { makeRows, ID } from '../test/fixtures.js';
import { buildView } from './buildView.js';
import AudioCard from './AudioCard.jsx';

const model = buildModel(applyRows(emptyTables(), makeRows()).tables);
const card = (sel) => render(<AudioCard audio={buildView(model, sel).audio} />);

describe('AudioCard (WEB-06, 3 estados)', () => {
  it('archivo en el servidor: metadata, punto mint, slot vacío y ningún botón (R7)', () => {
    const { container } = card(`portal:${ID.portalA}`);
    expect(screen.getByText('Audio del portal')).toBeInTheDocument();
    expect(screen.getByText('Audio final')).toBeInTheDocument();
    expect(screen.getByText('Con archivo.')).toBeInTheDocument();
    expect(screen.getByText('final · 01:15')).toBeInTheDocument();
    expect(screen.getByText('Archivo en el servidor')).toBeInTheDocument();
    expect(screen.queryByText('Sin archivo todavía')).toBeNull();
    const slot = container.querySelector('.player-slot');
    expect(slot).toBeEmptyDOMElement();
    expect(slot).toHaveAttribute('aria-hidden', 'true');
    expect(screen.queryAllByRole('button')).toHaveLength(0);
  });

  it('sin archivo todavía: bloque ámbar con el aviso y sin el estado "en el servidor"', () => {
    const { container } = card(`path:${ID.pathB}`);
    expect(screen.getByText('Audio del path')).toBeInTheDocument();
    expect(screen.getByText('Audio sin archivo')).toBeInTheDocument();
    expect(screen.getByText('final · 00:30')).toBeInTheDocument();
    expect(screen.getByText('Sin archivo todavía')).toBeInTheDocument();
    expect(screen.getByText('El audio está registrado, pero su archivo todavía no existe en el servidor.')).toBeInTheDocument();
    expect(container.querySelector('.empty')).not.toBeNull();
    expect(screen.queryByText('Archivo en el servidor')).toBeNull();
  });

  it('uuid de audio inexistente: mismo estado que sin audio asignado, sin bloque', () => {
    const { container } = card(`path:${ID.pathC}`);
    expect(screen.getByText('Este path no tiene audio asignado.')).toBeInTheDocument();
    expect(container.querySelector('.empty')).toBeNull();
    expect(screen.queryByText('Sin archivo todavía')).toBeNull();
  });

  it('sin audio asignado en un portal: texto dim con el copy del portal', () => {
    render(<AudioCard audio={{ label: 'Audio del portal', state: 'none', emptyText: 'Este portal no tiene audio asignado.' }} />);
    expect(screen.getByText('Este portal no tiene audio asignado.')).toHaveClass('dim');
  });

  it('nunca muestra clave de storage ni checksum (T-12-23) y el HTML de un título es texto (T-12-24)', () => {
    const { container } = card(`portal:${ID.portalA}`);
    expect(container.textContent).not.toMatch(/secreto|storage_key|checksum|\.mp3/);
    render(<AudioCard audio={{ label: 'x', state: 'nofile', title: '<img src=x onerror=alert(1)>', description: null, kind: 'final', duration: null, emptyText: 'e' }} />);
    expect(screen.getByText('<img src=x onerror=alert(1)>')).toBeInTheDocument();
    expect(document.querySelector('img')).toBeNull();
  });
});
