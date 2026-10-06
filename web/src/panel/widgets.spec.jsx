import { describe, it, expect, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { applyRows, buildModel, emptyTables } from '../data/model.js';
import { makeRows, ID } from '../test/fixtures.js';
import { buildView } from './buildView.js';
import CoverageStrip from './CoverageStrip.jsx';
import PortalTable from './PortalTable.jsx';
import EntityDetail from './EntityDetail.jsx';

const build = (rows = makeRows()) => buildModel(applyRows(emptyTables(), rows).tables);
const model = build();
const view = (sel, m = model) => buildView(m, sel);

describe('CoverageStrip (D-17)', () => {
  it('32 triggers y 1 hueco: 32 cuadros, 1 hueco entre el 16 y el 17, role=img y nota', () => {
    const { container } = render(<CoverageStrip strip={view(`path:${ID.pathA}`).strip} />);
    const img = screen.getByRole('img', { name: '32 triggers, 1 hueco' });
    expect(img.querySelectorAll('.sg:not(.gap)')).toHaveLength(32);
    const gaps = img.querySelectorAll('.sg.gap');
    expect(gaps).toHaveLength(1);
    expect(gaps[0].previousElementSibling).toBe(img.children[15]); // entre el cuadro 15 y el 16 (índices)
    expect(gaps[0].nextElementSibling).toBe(img.children[17]);
    expect(screen.getByText('Hueco de ≈ 40 m entre el trigger 016 y el 017.')).toBeInTheDocument();
    expect(container.querySelectorAll('[role="img"]')).toHaveLength(1);
  });

  it('con 5 huecos la nota muestra 3 y "+2 más"', () => {
    const rs = makeRows().map((r) => {
      if (r.table !== 'triggers' || r.payload.path_uuid !== ID.pathA) return r;
      const i = Number(r.payload.uuid.slice(-2));
      return { ...r, payload: { ...r.payload, longitude: r.payload.longitude + 0.00036 * Math.floor(i / 7) } };
    });
    const strip = view(`path:${ID.pathA}`, build(rs)).strip;
    expect(strip.cells.filter((c) => c.gap)).toHaveLength(5);
    render(<CoverageStrip strip={strip} />);
    expect(screen.getByText(/\+2 más$/)).toBeInTheDocument();
    expect(screen.getByText(/Hueco de/).textContent.match(/Hueco de/g)).toHaveLength(3);
  });

  it('sin huecos muestra la nota de solape; 2 huecos se escriben "2 huecos"', () => {
    render(<CoverageStrip strip={view(`path:${ID.pathB}`).strip} />);
    expect(screen.getByRole('img', { name: '3 triggers, 0 huecos' })).toBeInTheDocument();
    expect(screen.getByText('Los triggers se solapan de punta a punta: el path no tiene huecos.')).toBeInTheDocument();
    expect(view(`path:${ID.pathA}`).strip.ariaLabel).toBe('32 triggers, 1 hueco');
    const rs = makeRows().map((r) => (r.table === 'triggers' && r.payload.path_uuid === ID.pathA && Number(r.payload.uuid.slice(-2)) >= 25 ? { ...r, payload: { ...r.payload, longitude: r.payload.longitude + 0.0005 } } : r));
    expect(view(`path:${ID.pathA}`, build(rs)).strip.ariaLabel).toBe('32 triggers, 2 huecos');
  });

  it('un path con 0 triggers no tiene tira y el detalle dice "0 triggers"', () => {
    expect(view(`path:${ID.pathC}`).strip).toBeNull();
    const { container } = render(<CoverageStrip strip={null} />);
    expect(container).toBeEmptyDOMElement();
    render(<EntityDetail view={view(`path:${ID.pathC}`)} expanded onSelect={() => {}} onExpand={() => {}} />);
    expect(screen.getByText('0 triggers')).toBeInTheDocument();
    expect(screen.queryByRole('img')).toBeNull();
  });
});

describe('PortalTable (E8)', () => {
  const table = view(`path:${ID.pathA}`).table;

  it('encabezados con scope=col, filas por nombre y el nombre abre el portal', async () => {
    const onSelect = vi.fn();
    render(<PortalTable table={table} onSelect={onSelect} />);
    const heads = screen.getAllByRole('columnheader');
    expect(heads.map((h) => h.textContent)).toEqual(['#', 'Nombre', 'Radio', 'Offset', 'Posición']);
    heads.forEach((h) => expect(h).toHaveAttribute('scope', 'col'));
    const row = screen.getAllByRole('row')[1];
    expect(within(row).getByText('1')).toBeInTheDocument();
    expect(within(row).getByText('15 m')).toBeInTheDocument();
    await userEvent.setup().click(within(row).getByRole('button', { name: 'Portal A' }));
    expect(onSelect).toHaveBeenCalledWith(`portal:${ID.portalA}`);
  });

  it('un nombre largo lleva title con el texto completo', () => {
    const long = 'Portal ' + 'larguísimo '.repeat(8);
    render(<PortalTable table={{ title: 'Portales de la obra', rows: [{ ...table.rows[0], name: long }] }} onSelect={() => {}} />);
    expect(screen.getByRole('button', { name: long.trim() })).toHaveAttribute('title', long);
  });

  it('sin portales no se renderiza', () => {
    expect(view(`path:${ID.pathB}`).table).toBeNull();
    expect(render(<PortalTable table={null} onSelect={() => {}} />).container).toBeEmptyDOMElement();
  });
});

describe('EntityDetail: path y trigger', () => {
  const noop = () => {};

  it('path expandido: la tabla reemplaza a la lista y trae la tira', () => {
    render(<EntityDetail view={view(`path:${ID.pathA}`)} expanded onSelect={noop} onExpand={noop} />);
    expect(screen.getAllByRole('heading', { name: 'Portales de la obra' })).toHaveLength(1);
    expect(screen.getByRole('table')).toBeInTheDocument();
    expect(screen.getByRole('img', { name: /hueco/ })).toBeInTheDocument();
    expect(screen.getByText('Audio del path')).toBeInTheDocument();
  });

  it('path compacto: lista de portales y sin tabla ni tira', () => {
    render(<EntityDetail view={view(`path:${ID.pathA}`)} expanded={false} onSelect={noop} onExpand={noop} />);
    expect(screen.queryByRole('table')).toBeNull();
    expect(screen.queryByRole('img')).toBeNull();
    expect(screen.getByRole('button', { name: /Portal A/ })).toBeInTheDocument();
  });

  it('trigger: nota fija y vecinos con distancia; el primero no tiene Anterior', async () => {
    const onSelect = vi.fn();
    const { unmount } = render(<EntityDetail view={view(`trigger:${ID.trA(8)}`)} expanded={false} onSelect={onSelect} onExpand={noop} />);
    expect(screen.getByText(/Los triggers sólo marcan el camino: no tienen nombre ni sonido propio\. El sonido del path suena mientras el celular esté dentro de alguno\./)).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Vecinos en el path' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Anterior · trigger 008.*a 10 m/ })).toBeInTheDocument();
    await userEvent.setup().click(screen.getByRole('button', { name: /Siguiente · trigger 010.*a 10 m/ }));
    expect(onSelect).toHaveBeenCalledWith(`trigger:${ID.trA(9)}`);
    unmount();
    render(<EntityDetail view={view(`trigger:${ID.trA(0)}`)} expanded onSelect={noop} onExpand={noop} />);
    expect(screen.queryByRole('button', { name: /Anterior/ })).toBeNull();
    expect(screen.getByRole('button', { name: /Siguiente/ })).toBeInTheDocument();
  });

  it('el HTML de un nombre de portal es texto (T-12-24)', () => {
    const v = view(`path:${ID.pathA}`);
    v.table = { ...v.table, rows: [{ ...v.table.rows[0], name: '<img src=x onerror=alert(1)>' }] };
    render(<EntityDetail view={v} expanded onSelect={noop} onExpand={noop} />);
    expect(screen.getByText('<img src=x onerror=alert(1)>')).toBeInTheDocument();
    expect(document.querySelector('img')).toBeNull();
  });
});
