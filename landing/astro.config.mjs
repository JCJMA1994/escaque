import { defineConfig } from 'astro/config';

// La URL pública cambia por entorno (qa / prod); la fija el CI.
export default defineConfig({
  site: process.env.SITE_URL ?? 'http://localhost:4321',
  output: 'static',
  trailingSlash: 'never',
  build: { format: 'file', inlineStylesheets: 'auto' },
  compressHTML: true,
});
