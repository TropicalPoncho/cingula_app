import { useEffect, useRef } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import './map.css';
import { PANES, buildLayers, applySelection, syncGroups, coverBounds, targetBounds } from './layers.js';

// Único centro fijo permitido (D-02): sólo cuando ninguna obra visible tiene cobertura.
const FALLBACK = { center: [-42.08, -71.62], zoom: 11 };
const TILES = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'; // un solo host oficial: sin subdominios ni prefetch (política OSM)

const reducedMotion = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

// Leaflet imperativo dentro de React 19 (Pattern 3). Estado de Leaflet en refs; tres grupos de efectos:
// ciclo de vida del mapa, capas y encuadre. `fitKey` decide cuándo se re-encuadra (nunca por capas ni panel).
export default function MapView({ model, obras, capas, sel, fitKey, fitTarget, onSelect }) {
  const el = useRef(null);
  const mapRef = useRef(null);
  const built = useRef(null); // { groups, index } de las capas actuales
  const lastFit = useRef(); // fitKey ya aplicado a ESTE mapa
  const pendingFit = useRef(null); // encuadre a reintentar cuando el contenedor tenga tamaño
  const onSelectRef = useRef(onSelect);
  const capasRef = useRef(capas); // los efectos de capas leen el último valor sin depender de él
  const selRef = useRef(sel);
  useEffect(() => { onSelectRef.current = onSelect; });

  // Ciclo de vida. StrictMode monta dos veces: sin map.remove() en la limpieza, "already initialized" (Pitfall 4).
  useEffect(() => {
    const map = L.map(el.current, { zoomControl: false, attributionControl: false });
    map.setView(FALLBACK.center, FALLBACK.zoom);
    for (const [name, z] of Object.entries(PANES)) map.createPane(name).style.zIndex = z;
    L.tileLayer(TILES, { maxZoom: 19 }).addTo(map);
    L.control.zoom({ position: 'bottomright' }).addTo(map);
    mapRef.current = map;
    lastFit.current = undefined;
    pendingFit.current = null;

    // Leaflet sólo escucha window.resize: el panel cambia el ancho, así que se observa el contenedor.
    let raf;
    const ro = new ResizeObserver(() => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        map.invalidateSize({ pan: true }); // conserva el centro
        if (pendingFit.current?.()) pendingFit.current = null;
      });
    });
    ro.observe(el.current);
    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      map.remove();
      mapRef.current = null;
    };
  }, []);

  // Capas: se reconstruyen sólo si cambian modelo u obras visibles (Pitfall 7: selección y casillas no reconstruyen).
  useEffect(() => {
    const map = mapRef.current;
    const b = buildLayers(L, model, { obras, zoom: map.getZoom(), onSelect: (s) => onSelectRef.current(s) });
    built.current = b;
    syncGroups(map, b.groups, capasRef.current);
    applySelection(b.index, selRef.current, model);
    const onZoom = () => b.rescale(map.getZoom());
    map.on('zoomend', onZoom); // el corredor mide metros: su ancho en px cambia con el zoom
    return () => {
      map.off('zoomend', onZoom);
      Object.values(b.groups).forEach((g) => g.remove());
      built.current = null;
    };
  }, [model, obras]);

  useEffect(() => {
    capasRef.current = capas;
    if (built.current) syncGroups(mapRef.current, built.current.groups, capas);
  }, [capas]);

  useEffect(() => {
    selRef.current = sel;
    if (built.current) applySelection(built.current.index, sel, model);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- el modelo nuevo ya aplica la selección al reconstruir
  }, [sel]);

  // Encuadre (D-02, H4): pide a Leaflet recién con el contenedor medido; si todavía mide 0 queda pendiente.
  const requestFit = (bounds) => {
    const map = mapRef.current;
    const run = () => {
      const s = map.getSize();
      if (!(s.x > 0 && s.y > 0)) return false;
      const animate = !reducedMotion();
      if (bounds) map.fitBounds(bounds, { padding: [70, 70], maxZoom: 18, animate });
      else map.setView(FALLBACK.center, FALLBACK.zoom, { animate });
      return true;
    };
    map.whenReady(() => { pendingFit.current = run() ? null : run; });
  };

  useEffect(() => {
    if (fitKey == null || lastFit.current === fitKey) return;
    lastFit.current = fitKey;
    requestFit(coverBounds(L, obras));
    // ponytail: sólo `fitKey` re-encuadra; obras/modelo nuevos (refresco) no mueven el mapa
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fitKey]);

  useEffect(() => {
    const b = fitTarget && targetBounds(L, model, fitTarget.sel);
    if (b) requestFit(b);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fitTarget]);

  return (
    <div className="mapbox">
      <div className="mapview" ref={el} />
      <a className="attr" href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">
        © OpenStreetMap contributors
      </a>
    </div>
  );
}
