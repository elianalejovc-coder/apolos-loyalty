import React from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

function App() {
  return (
    <main className="shell">
      <div className="sun" aria-hidden="true">☼</div>
      <p className="eyebrow">APOLO'S · FIDELIZACIÓN</p>
      <h1>Una experiencia que merece volver.</h1>
      <p className="intro">
        La base del proyecto está lista. El siguiente paso es conectar Supabase
        y construir las vistas de clientes y personal con permisos seguros.
      </p>
      <div className="progress" aria-label="Vista previa de diez visitas">
        {Array.from({ length: 10 }, (_, i) => (
          <span className="stamp" key={i}>{i === 9 ? '✦' : String(i + 1).padStart(2, '0')}</span>
        ))}
      </div>
      <p className="footnote">10 visitas confirmadas por el equipo · 1 recompensa</p>
    </main>
  );
}

createRoot(document.getElementById('root')!).render(
  <React.StrictMode><App /></React.StrictMode>,
);
