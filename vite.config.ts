import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    outDir: 'dist',
    sourcemap: false,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules')) {
            if (id.includes('/react/') || id.includes('/react-dom/') || id.includes('/scheduler/')) {
              return 'vendor-react';
            }
            if (id.includes('/chess.js/') || id.includes('/chessground/')) {
              return 'vendor-chess';
            }
            if (id.includes('/ts-fsrs/') || id.includes('/idb/')) {
              return 'vendor-storage';
            }
            if (id.includes('/lucide-react/')) {
              return 'vendor-icons';
            }
          }
          if (id.includes('src/data/starterCourses.json')) {
            return 'starter-courses';
          }
          return undefined;
        },
      },
    },
  },
});
