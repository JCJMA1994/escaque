// Prueba de carga de partidas online contra qa (k6).
//
//   k6 run -e BASE_URL=https://api-escaque-qa.system-failed-tech.com \
//          -e LOAD_TEST_SECRET=... -e GAMES=200 -e THINK=2 tool/load/partidas.js
//
// Cada usuario virtual juega una partida completa controlando a los dos
// jugadores (load_w… y load_b…): elige nombre de usuario, crea, se une, juega
// 80 medias jugadas legales (moves.json, generadas con el motor), abandona y
// borra las dos cuentas. Requiere el servidor con LOAD_TEST_SECRET (solo qa).
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const BASE = __ENV.BASE_URL;
const SECRET = __ENV.LOAD_TEST_SECRET;
const GAMES = parseInt(__ENV.GAMES || '200', 10);
const THINK = parseFloat(__ENV.THINK || '2');
const MOVES = JSON.parse(open('./moves.json'));

if (!BASE || !SECRET) throw new Error('Faltan BASE_URL o LOAD_TEST_SECRET');

export const options = {
  scenarios: {
    partidas: { executor: 'per-vu-iterations', vus: GAMES, iterations: 1, maxDuration: '30m' },
  },
  thresholds: {
    'http_req_duration{endpoint:move}': ['p(95)<800'],
    'http_req_failed': ['rate<0.01'],
    jugadas_perdidas: ['count==0'],
    checks: ['rate>0.99'],
  },
  summaryTrendStats: ['avg', 'p(50)', 'p(95)', 'p(99)', 'max'],
};

const lost = new Counter('jugadas_perdidas');

function call(user, path, body, endpoint) {
  return http.post(`${BASE}${path}`, JSON.stringify(body || {}), {
    headers: { 'content-type': 'application/json', 'x-load-test': SECRET, 'x-test-user': user },
    tags: { endpoint },
  });
}

export default function () {
  const tag = `${__VU}x${Date.now() % 1000000}`;
  const white = `load_w${tag}`.replace('x', '_');
  const black = `load_b${tag}`.replace('x', '_');

  for (const user of [white, black]) {
    const r = call(user, '/v1/me/username', { username: `l${user.slice(5)}`.slice(0, 20) }, 'username');
    check(r, { 'nombre de usuario': (x) => x.status === 200 });
  }

  const created = call(white, '/v1/games', { kind: 'chess', seat: 0 }, 'create');
  if (!check(created, { 'crear partida': (x) => x.status === 200 })) return;
  const { id, code } = created.json();
  const joined = call(black, '/v1/games/join', { code }, 'join');
  if (!check(joined, { 'unirse': (x) => x.status === 200 })) return;

  for (let ply = 0; ply < MOVES.length; ply++) {
    const user = ply % 2 === 0 ? white : black;
    const r = call(user, `/v1/games/${id}/moves`, { ply, move: MOVES[ply] }, 'move');
    const ok = check(r, { 'jugada aceptada': (x) => x.status === 200 });
    if (!ok) {
      // 409 = la jugada no entró (conflicto o desfase): es lo que no debe pasar nunca.
      if (r.status === 409) lost.add(1);
      break;
    }
    sleep(THINK * (0.5 + Math.random()));
  }

  call(white, `/v1/games/${id}/resign`, {}, 'resign');
  for (const user of [white, black]) call(user, '/v1/me/delete', {}, 'delete');
}
