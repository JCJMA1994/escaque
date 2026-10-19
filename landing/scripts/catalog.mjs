// Publica el catálogo de problemas en la web (public/puzzles/catalog.json)
// a partir de los archivos de la app. Se ejecuta antes de cada compilación.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';

const app = new URL('../../tablero_app/assets/', import.meta.url);
const chess = JSON.parse(readFileSync(new URL('puzzles_chess.json', app), 'utf8'));
const draughts = JSON.parse(readFileSync(new URL('puzzles_draughts.json', app), 'utf8'));
const puzzles = [...chess, ...draughts];
const version = createHash('sha256').update(JSON.stringify(puzzles)).digest('hex').slice(0, 12);
const out = new URL('../public/puzzles/', import.meta.url);
mkdirSync(out, { recursive: true });
writeFileSync(new URL('catalog.json', out), JSON.stringify({ format: 1, version, puzzles }));
console.log(`catálogo de problemas: ${puzzles.length} (versión ${version})`);
