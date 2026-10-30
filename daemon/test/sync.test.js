// Tests de la sync côté Mac (daemon/sync.js) contre un vrai relais (relay/server.js) lancé en mémoire :
// création de la chaîne, publication chiffrée, envoi seulement si l'état change, commandes du téléphone (validation,
// rejeu, fenêtre de temps, actions interdites), suppression.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { creerSync, relaisValide, empreinteEtat } from '../sync.js';
import { encryptJson, decryptJson, deriveId, deriveWriteToken, fromWords, fromLink } from '../sync-crypto.js';
import { creerRelais } from '../../relay/server.js';

async function banc({ etat = { tick: 1, villages: [], privacy: 'normal' } } = {}) {
  const relais = creerRelais({ journal: () => {}, limites: { putParIdMs: 1 } });
  await new Promise((r) => relais.server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${relais.server.address().port}/`;
  const reglages = { privacy: 'normal' };
  const appels = [];
  const evenements = [];
  const b = {
    relais, base, reglages, appels, evenements,
    etat: JSON.stringify(etat),
    sauvegardes: 0,
  };
  b.sync = creerSync({
    reglages: () => reglages,
    sauverReglages: () => { b.sauvegardes++; },
    etatServi: () => b.etat,
    annexes: () => (reglages.privacy === 'flou' ? { rapport: null, journal: null, digest: null }
      : { rapport: { jour: 'bilan', semaine: 'rapport' }, journal: [{ t: 1, type: 'senat', text: 'x' }], digest: { since: Date.now(), commits: 2 } }),
    appliquer: {
      reclamer: (v) => { appels.push(['reclamer', v]); return v === 'rome' ? { ok: true } : { ok: false, erreur: 'no reward' }; },
      construire: (id) => { appels.push(['construire', id]); return { ok: true }; },
      reglage: (cle, val) => { appels.push(['reglage', cle, val]); reglages.privacy = val; return { ok: true }; },
    },
    evenement: (e) => evenements.push(e),
    automatique: false,
    intervallePutMs: 0,
    ecartMinMs: 0,
  });
  b.fin = () => relais.fermer();
  return b;
}

const S_DE = (b) => b.reglages.sync.secret;
const lireBlob = async (b) => {
  const r = await fetch(b.base + 'blob', { headers: { 'X-AImpire-Id': deriveId(S_DE(b)) } });
  return { r, octets: r.status === 200 ? Buffer.from(await r.arrayBuffer()) : null };
};
const envoyerCmd = (b, cmd) => fetch(b.base + 'cmd', { method: 'POST', headers: { 'X-AImpire-Id': deriveId(S_DE(b)) }, body: encryptJson(S_DE(b), cmd) });
const nonce = (n) => n.toString(16).padStart(32, '0');

test('relais accepté : https partout, http seulement en local', () => {
  assert.equal(relaisValide('https://aimpire.sidali.dev'), 'https://aimpire.sidali.dev/');
  assert.equal(relaisValide('http://127.0.0.1:7701'), 'http://127.0.0.1:7701/');
  assert.equal(relaisValide('http://localhost:7701/'), 'http://localhost:7701/');
  assert.equal(relaisValide('http://exemple.fr/'), null);
  assert.equal(relaisValide('ftp://exemple.fr/'), null);
  assert.equal(relaisValide('https://a:b@exemple.fr/'), null);
  assert.equal(relaisValide('pas une url'), null);
});

test('empreinte : ignore tick, peak, ago et digest.since', () => {
  const e = (tick, ago) => JSON.stringify({ tick, peak: { hiver: tick * 1.5, at: tick }, villages: [{ buildings: [{ id: 'a', ago }] }] });
  const a = (since) => ({ rapport: null, journal: [], digest: { since, commits: 1 }, commandes: [] });
  assert.equal(empreinteEtat(e(1, 61), a(1)), empreinteEtat(e(2, 119), a(2)));
  assert.equal(empreinteEtat(e(1, 61), a(1)), empreinteEtat(e(1, 4000), a(1)));
  const travail = (w) => JSON.stringify({ villages: [{ buildings: [{ id: 'a', working: w }] }] });
  assert.notEqual(empreinteEtat(travail(true), a(1)), empreinteEtat(travail(false), a(1)), 'un vrai changement compte');
  assert.notEqual(empreinteEtat(e(1, 1), a(1)), empreinteEtat(e(1, 1), { ...a(1), commandes: [{ nonce: 'x' }] }));
});

test('création : S tiré, enregistré, QR, lien et mots cohérents ; 409 si une chaîne existe', async () => {
  const b = await banc();
  try {
    assert.deepEqual(b.sync.etat(), { enabled: false });
    assert.equal(b.sync.creer('http://exemple.fr/').code, 400);
    const r = b.sync.creer(b.base);
    assert.equal(r.code, 200);
    const e = r.corps;
    assert.equal(e.enabled, true);
    assert.equal(e.relay, b.base);
    assert.match(b.reglages.sync.secret, /^[0-9a-f]{32}$/);
    assert.equal(b.sauvegardes, 1);
    assert.equal(e.id_court, deriveId(b.reglages.sync.secret).slice(0, 6));
    assert.equal(e.mots.length, 12);
    assert.equal(fromWords(e.mots).toString('hex'), b.reglages.sync.secret);
    assert.equal(fromLink(e.lien).toString('hex'), b.reglages.sync.secret);
    assert.ok(e.lien.startsWith(b.base + '#s='));
    assert.equal(e.qr.modules.length, e.qr.taille);
    assert.ok(e.qr.modules.every((l) => l.length === e.qr.taille && /^[01]+$/.test(l)));
    assert.equal(b.sync.creer(b.base).code, 409);
  } finally { b.sync.arreter(); await b.fin(); }
});

test('publication : blob chiffré et gzippé, opaque pour le relais, renvoyé seulement si l\'état change', async () => {
  const b = await banc();
  try {
    b.sync.creer(b.base);
    await b.sync.tour();
    const { r, octets } = await lireBlob(b);
    assert.equal(r.status, 200);
    assert.ok(!octets.toString('latin1').includes('villages'), 'rien de lisible dans le blob');
    const env = decryptJson(S_DE(b), octets);
    assert.equal(env.type, 'etat');
    assert.equal(env.v, 1);
    assert.ok(Math.abs(env.ts - Date.now()) < 5000);
    assert.deepEqual(env.etat, JSON.parse(b.etat));
    assert.equal(env.annexes.rapport.jour, 'bilan');
    assert.deepEqual(env.annexes.commandes, []);
    assert.ok(b.sync.etat().octets > 0);
    assert.ok(b.sync.etat().dernier_envoi > 0);
    const etag = r.headers.get('etag');
    b.etat = JSON.stringify({ tick: 2, villages: [], privacy: 'normal' });   // seul tick change : pas d'envoi
    await b.sync.tour();
    assert.equal((await lireBlob(b)).r.headers.get('etag'), etag);
    b.etat = JSON.stringify({ tick: 3, villages: [{ id: 'rome', buildings: [] }], privacy: 'normal' });
    await b.sync.tour();
    const apres = await lireBlob(b);
    assert.notEqual(apres.r.headers.get('etag'), etag);
    assert.equal(decryptJson(S_DE(b), apres.octets).etat.villages[0].id, 'rome');
  } finally { b.sync.arreter(); await b.fin(); }
});

test('mode discret : rapport, journal et digest ne quittent pas le Mac', async () => {
  const b = await banc();
  try {
    b.reglages.privacy = 'flou';
    b.sync.creer(b.base);
    await b.sync.tour();
    const env = decryptJson(S_DE(b), (await lireBlob(b)).octets);
    assert.equal(env.annexes.rapport, null);
    assert.equal(env.annexes.journal, null);
    assert.equal(env.annexes.digest, null);
  } finally { b.sync.arreter(); await b.fin(); }
});

test('commandes : appliquées avec les mêmes fonctions que les routes, résultats publiés, rejeu et abus refusés', async () => {
  const b = await banc();
  try {
    b.sync.creer(b.base);
    await b.sync.tour();
    const maintenant = Date.now();
    await envoyerCmd(b, { type: 'cmd', ts: maintenant, nonce: nonce(1), action: 'reglage', cle: 'privacy', val: 'flou' });
    await envoyerCmd(b, { type: 'cmd', ts: maintenant, nonce: nonce(2), action: 'reclamer', village: 'rome' });
    await envoyerCmd(b, { type: 'cmd', ts: maintenant, nonce: nonce(3), action: 'reclamer', village: 'carthage' });
    await envoyerCmd(b, { type: 'cmd', ts: maintenant - 11 * 60_000, nonce: nonce(4), action: 'construire', id: 'colisee' });
    await envoyerCmd(b, { type: 'cmd', ts: maintenant, nonce: nonce(5), action: 'action', kind: 'merge', session: 'x' });
    await envoyerCmd(b, { type: 'cmd', ts: maintenant, nonce: nonce(6), action: 'reglage', cle: 'voix', val: 'on' });
    await envoyerCmd(b, { type: 'etat', ts: maintenant, nonce: nonce(7) });
    // Rejeu par le relais : le même nonce une seconde fois.
    await envoyerCmd(b, { type: 'cmd', ts: maintenant, nonce: nonce(1), action: 'reglage', cle: 'privacy', val: 'normal' });
    // Blob chiffré avec une autre chaîne : mac faux, jeté sans trace.
    await fetch(b.base + 'cmd', { method: 'POST', headers: { 'X-AImpire-Id': deriveId(S_DE(b)) }, body: encryptJson('ffeeddccbbaa99887766554433221100', { type: 'cmd' }) });
    await b.sync.tour();
    assert.deepEqual(b.appels, [['reglage', 'privacy', 'flou'], ['reclamer', 'rome'], ['reclamer', 'carthage']]);
    assert.equal(b.reglages.privacy, 'flou');
    const env = decryptJson(S_DE(b), (await lireBlob(b)).octets);
    const res = Object.fromEntries(env.annexes.commandes.map((c) => [c.nonce, c]));
    assert.equal(env.annexes.commandes.length, 7, 'rejeu et mac faux ne laissent pas de trace');
    assert.equal(res[nonce(1)].ok, true);
    assert.equal(res[nonce(2)].ok, true);
    assert.equal(res[nonce(3)].ok, false);
    assert.equal(res[nonce(3)].erreur, 'no reward');
    assert.match(res[nonce(4)].erreur, /expired/);
    assert.match(res[nonce(5)].erreur, /not allowed/);
    assert.match(res[nonce(6)].erreur, /unknown setting/);
    assert.match(res[nonce(7)].erreur, /type/);
    assert.equal(b.evenements.length, 2);
    assert.ok(b.evenements.every((e) => e.type === 'telephone'));
    assert.equal(b.sync.etat().commandes, 7);
    assert.equal(env.annexes.rapport, null, 'la commande a activé le mode discret avant la publication');
  } finally { b.sync.arreter(); await b.fin(); }
});

test('suppression : blob effacé du relais, S oublié, nouvelle chaîne possible', async () => {
  const b = await banc();
  try {
    b.sync.creer(b.base);
    await b.sync.tour();
    const S = S_DE(b);
    assert.equal((await lireBlob(b)).r.status, 200);
    const r = await b.sync.supprimer();
    assert.equal(r.ok, true);
    assert.equal(r.relais, 'erased from the relay');
    assert.equal(b.reglages.sync, undefined);
    assert.deepEqual(b.sync.etat(), { enabled: false });
    assert.equal((await fetch(b.base + 'blob', { headers: { 'X-AImpire-Id': deriveId(S) } })).status, 404);
    assert.equal(b.sync.creer(b.base).code, 200);
    assert.notEqual(S_DE(b), S, 'nouveau secret');
  } finally { b.sync.arreter(); await b.fin(); }
});

test('jeton refusé par le relais : erreur lisible, nouvel essai dans 10 min au lieu d\'un arrêt définitif', async () => {
  let t = Date.now();
  let codePut = 401;
  const reglages = { sync: { enabled: true, relay: 'https://relais.exemple/', secret: '000102030405060708090a0b0c0d0e0f' } };
  const puts = [];
  const sync = creerSync({
    reglages: () => reglages, sauverReglages() {}, etatServi: () => '{"tick":1}', annexes: () => null,
    appliquer: {}, evenement() {}, automatique: false, maintenant: () => t,
    fetch: async (url, o = {}) => {
      if (o.method === 'PUT') puts.push(t);
      const status = o.method === 'PUT' ? codePut : 200;
      return { status, headers: new Headers(), json: async () => ({ cmds: [] }), body: null };
    },
  });
  await sync.tour();
  assert.match(sync.etat().erreur, /refuses this chain token/);
  await sync.tour();
  assert.equal(puts.length, 1, 'pas de nouvel essai tout de suite');
  t += 10 * 60_000 + 1;
  codePut = 200;
  await sync.tour();
  assert.equal(puts.length, 2, 'nouvel essai au bout de 10 min');
  assert.equal(sync.etat().erreur, '', 'la chaîne repart');
  sync.arreter();
});

test('commandes : refusées si antérieures au démarrage du Mac (nonces perdus au redémarrage)', async () => {
  const b = await banc();
  try {
    b.sync.creer(b.base);
    await b.sync.tour();
    await envoyerCmd(b, { type: 'cmd', ts: Date.now() - 60_000, nonce: nonce(1), action: 'reglage', cle: 'privacy', val: 'flou' });
    await b.sync.tour();
    assert.deepEqual(b.appels, []);
    const env = decryptJson(S_DE(b), (await lireBlob(b)).octets);
    assert.match(env.annexes.commandes[0].erreur, /before AImpire started/);
  } finally { b.sync.arreter(); await b.fin(); }
});

test('réglage : un réglage plus ancien que le dernier appliqué est refusé (réordonnancement, choix fait sur le Mac)', async () => {
  const b = await banc();
  try {
    b.sync.creer(b.base);
    await b.sync.tour();
    const t = Date.now() + 2000;
    // Le relais retient « normal » (envoyé d'abord) et le livre après « flou ».
    await envoyerCmd(b, { type: 'cmd', ts: t + 10, nonce: nonce(1), action: 'reglage', cle: 'privacy', val: 'flou' });
    await envoyerCmd(b, { type: 'cmd', ts: t, nonce: nonce(2), action: 'reglage', cle: 'privacy', val: 'normal' });
    await b.sync.tour();
    assert.deepEqual(b.appels, [['reglage', 'privacy', 'flou']]);
    assert.equal(b.reglages.privacy, 'flou');
    assert.equal(b.reglages.sync.dernierReglage, t + 10, 'enregistré dans config.json, donc après un redémarrage aussi');
    // Choix fait ensuite sur le Mac (touche H) : une commande du téléphone datée d'avant ne l'annule pas.
    await new Promise((r) => setTimeout(r, 60));
    const avant = Date.now() - 30;   // après le démarrage du Mac, mais avant le choix fait sur le Mac
    b.reglages.sync.dernierReglage = 0;
    b.sync.reglageLocal();
    await envoyerCmd(b, { type: 'cmd', ts: avant, nonce: nonce(3), action: 'reglage', cle: 'privacy', val: 'normal' });
    await b.sync.tour();
    assert.equal(b.appels.length, 1);
    const env = decryptJson(S_DE(b), (await lireBlob(b)).octets);
    const res = Object.fromEntries(env.annexes.commandes.map((c) => [c.nonce, c]));
    assert.match(res[nonce(2)].erreur, /newer/);
    assert.match(res[nonce(3)].erreur, /newer/);
  } finally { b.sync.arreter(); await b.fin(); }
});

test('mode discret : GET /sync ne montre ni lien, ni mots, ni QR ; blob bourré au palier de 16 Kio', async () => {
  const b = await banc();
  try {
    const e = b.sync.creer(b.base, { masquer: true }).corps;
    assert.equal(e.masque, true);
    assert.equal(e.lien, undefined);
    assert.equal(e.mots, undefined);
    assert.equal(e.qr, undefined);
    assert.equal(e.id_court.length, 6);
    assert.ok(b.sync.etat().lien, 'visible hors mode discret');
    await b.sync.tour();
    const { octets } = await lireBlob(b);
    assert.equal((octets.length - 49) % 16384, 0, 'taille au palier');
    assert.equal(decryptJson(S_DE(b), octets).type, 'etat');
  } finally { b.sync.arreter(); await b.fin(); }
});

test('publications : deux envois dus à un changement sont espacés (10 s par défaut), une commande passe tout de suite', async () => {
  let t = Date.now();
  const reglages = { sync: { enabled: true, relay: 'https://relais.exemple/', secret: '000102030405060708090a0b0c0d0e0f' } };
  const puts = [];
  let etat = '{"tick":1,"n":1}';
  const sync = creerSync({
    reglages: () => reglages, sauverReglages() {}, etatServi: () => etat, annexes: () => null,
    appliquer: {}, evenement() {}, automatique: false, maintenant: () => t,
    fetch: async (url, o = {}) => { if (o.method === 'PUT') puts.push(t); return { status: 200, headers: new Headers(), json: async () => ({ cmds: [] }), body: null }; },
  });
  await sync.tour();
  etat = '{"tick":2,"n":2}';
  t += 3000;
  await sync.tour();
  assert.equal(puts.length, 1, 'changement 3 s après un envoi : attend');
  t += 7000;
  await sync.tour();
  assert.equal(puts.length, 2, 'repris 10 s après');
  sync.arreter();
});
