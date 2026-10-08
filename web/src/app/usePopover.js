import { useEffect, useRef, useState } from 'react';

// Popover no modal (pill de sync, menú de capas del mapa): Esc o clic afuera lo cierran y el foco vuelve al botón.
// `wrap` envuelve botón + contenido; `button` es el ref del botón que lo abre.
export function usePopover() {
  const [open, setOpen] = useState(false);
  const wrap = useRef(null);
  const button = useRef(null);

  useEffect(() => {
    if (!open) return undefined;
    const close = () => { setOpen(false); button.current.focus(); };
    // ponytail: Esc en CAPTURA + preventDefault; el Esc del panel lateral ignora `defaultPrevented`, así que
    // cerrar el menú nunca cierra también el panel. Sin esto, con el foco dentro del popover caerían los dos.
    const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); close(); } };
    const onDown = (e) => { if (!wrap.current.contains(e.target)) close(); };
    document.addEventListener('keydown', onKey, true);
    document.addEventListener('pointerdown', onDown);
    return () => {
      document.removeEventListener('keydown', onKey, true);
      document.removeEventListener('pointerdown', onDown);
    };
  }, [open]);

  return { open, setOpen, wrap, button };
}
