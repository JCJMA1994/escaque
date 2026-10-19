// Tests de firestore.rules contra el emulador de Firestore.
// Desde la raíz del monorepo:
//   npx firebase-tools@15.32.1 emulators:exec --only firestore --project demo-escaque \
//     "npm test --prefix firebase/tests"
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-escaque',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(async () => env?.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'games/g1'), {
      kind: 'chess', members: ['ana', 'joao'], players: ['ana', 'joao'], status: 'active', moves: [],
    });
    await setDoc(doc(db, 'invites/K7Q2ZP'), { gameId: 'g1' });
    await setDoc(doc(db, 'usernames/ana'), { uid: 'ana' });
    await setDoc(doc(db, 'users/ana'), { username: 'ana', notify: true, reminders: true });
  });
});

// Tipos de sesión
const google = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'google.com' } }).firestore();
const verified = (uid) =>
  env.authenticatedContext(uid, { email_verified: true, firebase: { sign_in_provider: 'password' } }).firestore();
const unverified = (uid) =>
  env.authenticatedContext(uid, { email_verified: false, firebase: { sign_in_provider: 'password' } }).firestore();
const anonymous = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous' } }).firestore();
const nobody = () => env.unauthenticatedContext().firestore();

describe('partidas', () => {
  test('un jugador con cuenta de Google la lee', () => assertSucceeds(getDoc(doc(google('ana'), 'games/g1'))));
  test('un jugador con correo verificado la lee', () => assertSucceeds(getDoc(doc(verified('joao'), 'games/g1'))));
  test('con el correo sin verificar, no', () => assertFails(getDoc(doc(unverified('ana'), 'games/g1'))));
  test('con sesión anónima, no', () => assertFails(getDoc(doc(anonymous('ana'), 'games/g1'))));
  test('quien no juega, no', () => assertFails(getDoc(doc(google('luis'), 'games/g1'))));
  test('sin sesión, no', () => assertFails(getDoc(doc(nobody(), 'games/g1'))));
  test('la lista de mis partidas sí', () =>
    assertSucceeds(getDocs(query(collection(google('ana'), 'games'), where('members', 'array-contains', 'ana')))));
  test('la lista de todas las partidas, no', () => assertFails(getDocs(collection(google('ana'), 'games'))));
  test('nadie escribe partidas desde la app (solo el servidor)', async () => {
    await assertFails(updateDoc(doc(google('ana'), 'games/g1'), { moves: ['e2e4'] }));
    await assertFails(setDoc(doc(google('ana'), 'games/nueva'), { members: ['ana'] }));
    await assertFails(deleteDoc(doc(google('ana'), 'games/g1')));
  });
});

describe('invitaciones y nombres de usuario', () => {
  test('las invitaciones no se leen', () => assertFails(getDoc(doc(google('luis'), 'invites/K7Q2ZP'))));
  test('las reservas de nombre no se leen', () => assertFails(getDoc(doc(google('ana'), 'usernames/ana'))));
  test('ni se escriben', () => assertFails(setDoc(doc(google('luis'), 'usernames/luis'), { uid: 'luis' })));
});

describe('amistades y valoraciones', () => {
  test('una amistad la leen sus miembros y nadie más', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'friendships/ana_joao'), { users: ['ana', 'joao'], status: 'accepted' });
      await setDoc(doc(ctx.firestore(), 'ratings/ana'), { ratings: {} });
      await setDoc(doc(ctx.firestore(), 'leaderboards/chess'), { entries: [] });
    });
    await assertSucceeds(getDoc(doc(google('joao'), 'friendships/ana_joao')));
    await assertFails(getDoc(doc(google('luis'), 'friendships/ana_joao')));
    await assertFails(setDoc(doc(google('ana'), 'friendships/ana_joao'), { users: ['ana', 'joao'], status: 'accepted' }));
  });
  test('valoración propia sí, ajena no; clasificación con sesión', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'ratings/ana'), { ratings: {} });
      await setDoc(doc(ctx.firestore(), 'leaderboards/chess'), { entries: [] });
    });
    await assertSucceeds(getDoc(doc(google('ana'), 'ratings/ana')));
    await assertFails(getDoc(doc(google('joao'), 'ratings/ana')));
    await assertFails(setDoc(doc(google('ana'), 'ratings/ana'), { ratings: { chess: { r: 3000 } } }));
    await assertSucceeds(getDoc(doc(google('joao'), 'leaderboards/chess')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'leaderboards/chess')));
  });
  test('la preferencia de solicitudes la escribe el dueño', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'users/ana'), { notify: true }));
    await assertSucceeds(updateDoc(doc(google('ana'), 'users/ana'), { friendRequests: false }));
  });
});

describe('compras', () => {
  test('nadie lee ni escribe compras desde la app', async () => {
    await assertFails(getDoc(doc(google('ana'), 'purchases/abc')));
    await assertFails(setDoc(doc(google('ana'), 'purchases/abc'), { uid: 'ana' }));
  });
  test('«sin anuncios» solo lo escribe el servidor', () =>
    assertFails(updateDoc(doc(google('ana'), 'users/ana'), { adFree: true })));
});

describe('perfil', () => {
  test('leo el mío aunque el correo no esté verificado', () =>
    assertSucceeds(getDoc(doc(unverified('ana'), 'users/ana'))));
  test('no leo el de otra persona', () => assertFails(getDoc(doc(google('luis'), 'users/ana'))));
  test('cambio mis preferencias de avisos aunque exista mi nombre de usuario', () =>
    assertSucceeds(updateDoc(doc(google('ana'), 'users/ana'), { notify: false })));
  test('no cambio mi nombre de usuario (solo el servidor)', () =>
    assertFails(updateDoc(doc(google('ana'), 'users/ana'), { username: 'reina' })));
  test('guardo mi idioma (es o en) para los avisos', async () => {
    await assertSucceeds(updateDoc(doc(google('ana'), 'users/ana'), { locale: 'en' }));
    await assertFails(updateDoc(doc(google('ana'), 'users/ana'), { locale: 'fr' }));
  });
  test('preferencias con tipo incorrecto, no', () =>
    assertFails(updateDoc(doc(google('ana'), 'users/ana'), { notify: 'sí' })));
  test('creo mi perfil solo con preferencias', async () => {
    await assertSucceeds(setDoc(doc(google('luis'), 'users/luis'), { notify: true }));
    await assertFails(setDoc(doc(google('marta'), 'users/marta'), { notify: true, username: 'marta' }));
  });
});

describe('dispositivos', () => {
  test('registro el mío', () =>
    assertSucceeds(setDoc(doc(google('ana'), 'users/ana/devices/tok1'), { platform: 'android' })));
  test('no en la cuenta de otra persona', () =>
    assertFails(setDoc(doc(google('luis'), 'users/ana/devices/tok2'), { platform: 'android' })));
  test('sin campos extra', () =>
    assertFails(setDoc(doc(google('ana'), 'users/ana/devices/tok3'), { platform: 'android', admin: true })));
  test('lo borro al cerrar sesión', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'users/ana/devices/tok4'), { platform: 'android' }));
    await assertSucceeds(deleteDoc(doc(google('ana'), 'users/ana/devices/tok4')));
  });
});
