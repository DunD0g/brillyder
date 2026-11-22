import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';

declare global {
  interface Window {
    __brillyderWaitingWorker?: ServiceWorker | null;
  }
}

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    const notifyUpdate = (worker: ServiceWorker | null) => {
      if (!worker) return;
      window.__brillyderWaitingWorker = worker;
      window.dispatchEvent(new CustomEvent('brillyder-sw-update'));
    };

    navigator.serviceWorker
      .register('./sw.js')
      .then((reg) => {
        if (reg.waiting && navigator.serviceWorker.controller) {
          notifyUpdate(reg.waiting);
        }
        reg.addEventListener('updatefound', () => {
          const installing = reg.installing;
          if (!installing) return;
          installing.addEventListener('statechange', () => {
            if (installing.state === 'installed' && navigator.serviceWorker.controller) {
              notifyUpdate(reg.waiting ?? installing);
            }
          });
        });
      })
      .catch(() => undefined);
  });
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
