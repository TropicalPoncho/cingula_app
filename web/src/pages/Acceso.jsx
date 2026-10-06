import { useState } from 'react';
import { navigate, useQuery } from '../app/router.jsx';
import { setKey } from '../app/session.js';
import logo from '../ds/logo-mark-light.png';

const E401 = {
  label: 'Clave rechazada',
  msg: 'El servidor respondió 401. Revisá que la clave esté completa y que siga vigente.',
};
const EVENCIDA = { label: 'Clave rechazada', msg: 'La clave dejó de ser válida. Ingresala de nuevo.' };
const ERED = { label: 'Sin conexión', msg: 'No se pudo llegar al servidor. Reintentá cuando tengas conexión.' };

export default function Acceso() {
  const motivo = useQuery().get('motivo');
  const [error, setError] = useState(motivo === '401' ? EVENCIDA : null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e) {
    e.preventDefault();
    const key = new FormData(e.currentTarget).get('key').trim();
    if (!key) return; // campo vacío: ninguna request
    setLoading(true);
    setError(null);
    try {
      // La clave sólo viaja en Authorization; nunca en la URL ni en logs.
      const res = await fetch('/sync/state', { headers: { Authorization: 'Bearer ' + key }, cache: 'no-store' });
      if (res.status === 200) {
        setKey(key);
        navigate('/', { replace: true });
        return;
      }
      setError(res.status === 401 ? E401 : ERED);
    } catch {
      setError(ERED);
    }
    setLoading(false);
  }

  return (
    <main className="acceso">
      <svg className="acceso-waves" viewBox="0 0 1440 400" preserveAspectRatio="none" aria-hidden="true">
        <path
          d="M0 220 C 120 120 240 320 360 220 S 600 120 720 220 S 960 320 1080 220 S 1320 120 1440 220"
          style={{ fill: 'none', stroke: 'var(--c-mint)', strokeWidth: 1.25, vectorEffect: 'non-scaling-stroke' }}
        />
        <path
          d="M0 240 C 140 150 260 330 380 240 S 620 150 740 240 S 980 330 1100 240 S 1340 150 1440 240"
          style={{ fill: 'none', stroke: 'var(--c-azure)', strokeWidth: 1.25, vectorEffect: 'non-scaling-stroke', opacity: 0.7 }}
        />
      </svg>
      <section className="acceso-card" aria-labelledby="t">
        <img src={logo} alt="" />
        <div className="cg-portal-type">Cíngula</div>
        <h1 id="t">Ingresá la clave de acceso</h1>
        <p>Esta web sólo lee. La clave vive en esta pestaña y se borra al cerrarla.</p>
        <form onSubmit={onSubmit}>
          <label className="lbl" htmlFor="k">API key</label>
          <input id="k" name="key" className="inp" type="password" autoComplete="off" placeholder="WEB_API_KEY" />
          {error && (
            <div role="alert" className="perr">
              <span className="lbl">{error.label}</span>
              <span>{error.msg}</span>
            </div>
          )}
          <button type="submit" className="btn btn-p" disabled={loading}>
            {loading ? 'Entrando…' : 'Entrar a la web'}
          </button>
        </form>
        <p className="nota">Sin registro ni “recordarme”. Requiere conexión.</p>
      </section>
    </main>
  );
}
