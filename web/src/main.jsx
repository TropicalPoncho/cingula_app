import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './ds/tokens.css';
import './ds/bundle.css';
import './app/shell.css';
import App from './app/App.jsx';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
